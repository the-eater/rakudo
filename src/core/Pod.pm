my class Pod::Block {
    has %.config;
    has @.content;

    sub pod-gist(Pod::Block $pod, $level = 0) {
        my $leading = ' ' x $level;
        my %confs;
        my @chunks;
        for <config name level caption type> {
            my $thing = $pod.?"$_"();
            if $thing {
                %confs{$_} = $thing ~~ Iterable ?? $thing.perl
                                                !! $thing.Str;
            }
        }
        @chunks = $leading, $pod.^name, (%confs.perl if %confs), "\n";
        for $pod.content.list -> $c {
            if $c ~~ Pod::Block {
                @chunks.push: pod-gist($c, $level + 2);
            }
            elsif $c ~~ Positional {
                @chunks.push: $c>>.Str.perl.indent($level + 2), "\n";
            }
            else {
                @chunks.push: $c.Str.indent($level + 2), "\n";
            }
        }
        @chunks.join;
    }

    multi method gist(Pod::Block:D:) {
        pod-gist(self)
    }
}

my class Pod::Block::Para is Pod::Block {
}

my class Pod::Block::Named is Pod::Block {
    has $.name;
}

my class Pod::Block::Comment is Pod::Block { }

my class Pod::Block::Code is Pod::Block {
    has @.allowed;
}

my class Pod::Block::Declarator is Pod::Block {
    has $.WHEREFORE;
    has @!leading;
    has @!trailing;

    submethod BUILD(:@!leading, :@!trailing) {}

    method set_docee($d) {
        $!WHEREFORE = $d
    }
    method Str {
        $.content
    }
    multi method gist(Pod::Block::Declarator:D:) {
        $.content
    }

    method content {
        my @result = @!leading;
        @result.push: @!trailing;
        @result.join("\n")
    }

    method leading  { @!leading  ?? @!leading.join("\n")  !! Any }
    method trailing { @!trailing ?? @!trailing.join("\n") !! Any }

    method _add_leading($addition) {
        @!leading.push: ~$addition;
    }

    method _add_trailing($addition) {
        @!trailing.push: ~$addition;
    }
}

my class Pod::Block::Table is Pod::Block {
    has $.caption;
    has @.headers; # optional, may be empty
}

my class Pod::FormattingCode is Pod::Block {
    has $.type;
    has @.meta;
}

my class Pod::Heading is Pod::Block {
    has $.level;
}

my class Pod::Item is Pod::Block {
    has $.level;
}

class Pod::Config {
    has $.type;
    has %.config;
}

# for passing raw instructions to specific backends
class Pod::Raw {
    has $.target;
    has $.content;
}

# vim: ft=perl6 expandtab sw=4
