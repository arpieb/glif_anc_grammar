from nltk.corpus.reader.bracket_parse import *
import sys

def extract_cnf_from_anc_masc_ptb(path):
    reader = BracketParseCorpusReader(path, '.*/.*/.*\.mrg', detect_blocks='sexpr')

    #print "\n".join(reader.fileids())

    terminal = set()
    binary = dict()
    for fileid in reader.fileids():
        for sent in reader.parsed_sents(fileid):
            if sent.label() != 'CODE':
                try:
                    sent.chomsky_normal_form()
                    for p in sent.productions():
                        if p.is_lexical():
                            terminal.add(p.unicode_repr())
                        else:
                            #binary.add(p.unicode_repr())
                            lhs = p.lhs().unicode_repr()
                            rule = p.unicode_repr()
                            if lhs not in binary:
                                binary[lhs] = dict()
                            if rule not in binary[lhs]:
                                binary[lhs][rule] = 1
                            else:
                                binary[lhs][rule] += 1
                except Exception:
                    pass

    print "TERMINALS"
    print "\n".join(terminal)

    print

    print "BINARIES"
    for (lhs, rules) in binary.iteritems():
        num_rules = sum([x for x in rules.itervalues()])
        #print lhs, num_rules
        for (rule, count) in rules.iteritems():
            print rule, (1.0 * count / num_rules)

if __name__ == "__main__":
    #print sys.argv
    path = sys.argv[1] if len(sys.argv) > 1 else './'
    extract_cnf_from_anc_masc_ptb(path)
