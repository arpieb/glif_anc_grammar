defmodule GlifAncGrammar.MASC.PTB do
  @moduledoc """
  This grammar module provides a codified version of a CNF grammar extracted from
  the [American National Corpus' Manually Annotated Sub-Corpus](http://www.anc.org/data/masc/)
  Penn Treebank (PTB) source files for English.

  The CNF grammar included here was generated using [NLTK](http://www.nltk.org/) to process the PTB
  annotations from the v3.0.0 release of MASC PTB data.  The Python script is
  included in this module's directory as `anc_masc_ptb_extract.py`.

  (If anyone knows of - or would like to build - a PTB native parser in Elixir
  that can extract grammar production rules, please feel free to contribute!)
  """
  @behaviour Glif.Grammar.CNF

  # Some handy module attributes for locating assets.
  @external_resource cnf_path = Path.join([__DIR__, "anc_masc_ptb_v300.cnf"])

  defmodule GrammarLoader do
    @moduledoc ~S"""
    Helper module to be used only with the Glif.Grammar.CNF.ANC.MASC.PTB module to process the CNF export.
    """

    # Struct holds the major sections we will extract from the PCFG.
    defstruct lexicon: %{}, rules: %{}

    # Process CNF export file
    def parse_cnf(cnf_path) do
        File.stream!(cnf_path, [:read, :utf8])
        |> Enum.reduce(%GrammarLoader{}, &GrammarLoader.process_line/2)
    end

    # Process a line from the file into the grammar being built.
    # Note the normal param order is swapped since this is being called from a reduce function.
    def process_line(line, grammar) do
      line = String.trim(line)

      # Define regex patterns for lexicon/rule extraction
      re_lexicon = ~r/(?<left>\S+)\s+->\s+['"](?<right>.+)['"]/ # Example: VBZ -> 'exaggerates'
      re_rule = ~r/(?<left>\S+)\s+->\s+(?<r1>\S+)\s+(?<r2>\S+)\s+(?<prob>[\d-.e]+)/ # Example: NP-SBJ -> DT NP-SBJ|<NNP-NN-NN> 8.86147738551e-05

      # Pipe grammar through potential lexicon/rule updates from current CNF line
      grammar
      |> update_lexicon(Regex.named_captures(re_lexicon, line))
      |> update_rules(Regex.named_captures(re_rule, line))
    end

    # Add/update terminal from CNF lexicon.
    defp update_lexicon(grammar, %{"left" => left, "right" => right}) do
      lexicon = Map.get(grammar, :lexicon, %{})
      symbols = [{left, right} | Map.get(lexicon, right, [])]
      Map.put(grammar, :lexicon, Map.put(lexicon, right, symbols))
    end
    defp update_lexicon(grammar, _other), do: grammar

    # Add/update binary grammar from CNF rules.
    defp update_rules(grammar, %{"left" => left, "r1" => r1, "r2" => r2, "prob" => prob}) do
      b_grammar = Map.get(grammar, :rules, [])
      key = {r1, r2}
      rules = [{left, key, String.to_float(prob)} | Map.get(b_grammar, key, [])]
      Map.put(grammar, :rules, Map.put(b_grammar, key, rules))
    end
    defp update_rules(grammar, _other), do: grammar
  end

  # Get start time for reporting
  start = System.monotonic_time()
  IO.puts("Compiling ANC MASC PTB CNF (whew!) export to static lookups takes a while...")

  # Extract grammar maps from Stanford CoreNLP English PCFG export
  IO.puts("Parsing CNF export...")
  %{lexicon: lexicon, rules: rules} = GrammarLoader.parse_cnf(@external_resource)
  IO.puts("Extracted " <> Integer.to_string(Enum.count(lexicon)) <> " terminals")
  IO.puts("          " <> Integer.to_string(Enum.count(rules)) <> " rules")

  IO.puts("Generating grammar function heads...")

  # Util functions to perform grammar lookups
  defp get_lexicon(), do: unquote(Macro.escape(lexicon))
  defp get_rules(), do: unquote(Macro.escape(rules))

  # End timer
  elapsed = (System.monotonic_time() - start) |> System.convert_time_unit(:native, :millisecond)
  IO.puts("Codified ANC MASC PTB CNF export in #{elapsed}ms")

  @doc ~S"""
  Perform a lookup for a terminal in the CNF grammar.

  The CNF rule is of the form A -> <word> and the lookup is performed on the word
  to return a list of terminal symbol matches in the form `[{A, <word>, <seen>}]`
  or `nil` if no match.
  """
  def terminal(word) do
    Map.get(get_lexicon(), word, nil)
  end

  @doc ~S"""
  Perform a lookup for a binary rule in the CNF grammar.

  The CNF rule is of the form A -> BC and the lookup is performed on B and C to
  return a list of matches in the form `[{A, {B, C}, <probability>}]` or `nil` if
  no match.
  """
  def rule(r1, r2) when is_tuple(r1) and is_tuple(r2) do
    r1_key = elem(r1, 0)
    r2_key = elem(r2, 0)
    get_rules()
    |> Map.get({r1_key, r2_key}, nil)
    |> process_rule_lookup(r1, r2)
  end

  # Util function to help process binary grammar lookup results
  defp process_rule_lookup(matches, r1, r2) when is_list(matches) do
    for {left, _, prob} <- matches do
      {left, {r1, r2}, prob}
    end
  end
  defp process_rule_lookup(nil, _r1, _r2), do: nil

  @doc ~S"""
  Tokenizes the provided String and returns a list of String tokens.
  """
  def tokenize(sent) do
    # Dirt. Simple. For testing only.
    # TODO implement a real tokenizer...
    sent
    |> String.trim()
    |> String.split()
    |> process_tokens()
  end

  # Process the list of tokens partially based on pseudocode from:
  # https://spacy.io/docs/usage/customizing-tokenizer#how-tokenizer-works
  defp process_tokens([]), do: []
  defp process_tokens(tokens) do
    ws_token = hd(tokens)
    cond do
      # Check to see if this terminal exists as-is.
      terminal(ws_token) ->
        [ws_token]

      # If not, try mucking with capitalization to see if we get a hit.
      ws_token |> String.downcase() |> terminal() ->
        [ws_token |> String.downcase()]
      ws_token |> String.upcase() |> terminal() ->
        [ws_token |> String.upcase()]
      ws_token |> String.capitalize() |> terminal() ->
        [ws_token |> String.capitalize()]

      # OK, nothing worked so maybe it's a "complex" token...
      true ->
        process_complex_token(ws_token)
    end
    |> Enum.concat(process_tokens(tl(tokens)))
  end

  # Process a token that doesn't currently match any terminal rules.
  defp process_complex_token(token) do
    # Simplistic approach; split on punctuation and try to process resulting list of tokens.
    tokens = String.split(token, ~r{[\W]}, trim: true, include_captures: true)
    cond do
      length(tokens) > 1 ->
        process_tokens(tokens)
      true ->
        tokens
    end
  end

end
