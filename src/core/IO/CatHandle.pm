my class IO::CatHandle is IO::Handle {
    has @!handles;
    has IO::Handle $!active-handle;

    method new (*@handles, :$pre-open-all) {
        if $pre-open-all {
            for @handles {
                when IO::Handle {
                    next if .opened;
                    $_ = .open: :r orelse .throw;
                }
                $_ = .IO.open: :r orelse .throw;
            }
        }
        $_ := self.bless: :@handles;
        $_!NEXT-HANDLE;
        $_
    }

    method !NEXT-HANDLE {
      # Set $!active-handle to the next handle in line, opening it if necessary
      nqp::if(
        @handles,
        nqp::if(
          nqp::istype(($_ := @handles.shift), IO::Handle),
          nqp::if(
            .opened,
            ($!active-handle = $_),
            nqp::if(
              nqp::istype(($!active-handle = .open: :r), Failure),
              .throw,
              $_)),
          nqp::if(
            nqp::istype(($_ := .IO.open: :r), Failure),
            .throw,
            $_),
        ($!active-handle = Nil))
    }

    method !CALL-ON-ALL ($meth, |c) {
        # Call method $meth on all filehandles, returns the return value of
        # the last call. Uses `try` to catch any throwage and ignores it
        nqp::stmts(
          (my int $els = @!handles.elems),
          (my int $i = -1),
          nqp::while(
            nqp::isne_i($els, $i = nqp::add_i($i, 1)),
            my $_ := try @!handles.AT-POST($i)."$meth"(|c)),
          $_)
    }

    method !CALL-ON-ACTIVE ($meth, \no-handle, |c) {
        # Call $meth on active handle, passing |c as arguments to it.
        # If no handle is active, return the $no-active value.
        # NOTE: keep no-handle as RAW, so that Nils get passed around correctly
        $!active-handle.DEFINITE ?? $!active-handle."$meth"(|c) !! no-handle
    }

    method close    (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'close',    |c  }
    method DESTROY  (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'DESTROY',  |c  }
    method encoding (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'DESTROY',  |c  }
    method flush    (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'flush',    |c  }
    method lock     (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'lock',     |c  }
    method print    (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'print',    |c  }
    method print-nl (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'print-nl', |c  }
    method printf   (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'printf',   |c  }
    method put      (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'put',      |c  }
    method say      (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'say',      |c  }
    method seek     (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'seek',     |c  }
    method unlock   (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'unlock',   |c  }
    method write    (IO::CatHandle:D: |c) { self!CALL-ON-ALL: 'write',    |c  }

    method eof      (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'eof',     True }
    method IO       (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'IO',       Nil }
    method iterator (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'iterator', Nil }
    method opened   (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'opened', False }
    method path     (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'path',     Nil }
    method tell     (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'tell',     Nil }
    method Str      (IO::CatHandle:D:) { self!CALL-ON-ACTIVE: 'Str',       '' }
    method native-descriptor(IO::CatHandle:D:) {
        self!CALL-ON-ACTIVE: 'native-descriptor', Nil
    }
    method open (IO::CatHandle:D:) { $!active-handle }
    method gist (IO::CatHandle:D:) { self.^name ~ "($!active-handle.gist())" }
    method perl (IO::CatHandle:D:) {
        my $handles = ($!active-handle, |@!handles);
        self.^name ~ ".new($handles.perl())"
    }

    method chomp is rw {
        Proxy.new(
            FETCH => { self!CALL-ON-ALL: 'nl-in', Nil },
            STORE => -> $, $chomp { .chomp = $chomp for @!handles },
        );
    }

    method nl-in is rw {
        Proxy.new(
            FETCH => { self!CALL-ON-ACTIVE: 'nl-in', Nil },
            STORE => -> $, $nl-in { .nl-in = $nl-in for @!handles },
        );
    }

    method getc {
        nqp::stmts(
          nqp::while(
            nqp::eqaddr(($_ := self!CALL-ON-ACTIVE: 'getc', Nil), Nil)
            && nqp::defined($!active-handle),
            nqp::null),
          $_),
    }

    method get {
        nqp::stmts(
          nqp::while(
            nqp::eqaddr(($_ := self!CALL-ON-ACTIVE: 'get', Nil), Nil)
            && nqp::defined($!active-handle),
            nqp::null),
          $_),
    }
    # comb
    # words
    # lines
    # split
    # read
    # readchars
    # slurp
    # Supply
}

# vim: ft=perl6 expandtab sw=4
