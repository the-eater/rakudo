my class BagHash does Baggy {

#--- interface methods
    multi method WHICH(BagHash:D:) { self.Mu::WHICH }
    multi method AT-KEY(BagHash:D: \k) is raw {
        Proxy.new(
          FETCH => {
              nqp::if(
                (my $raw := self.raw_hash)
                  && nqp::existskey($raw,(my $which := k.WHICH)),
                nqp::getattr(
                  nqp::decont(nqp::atkey($raw,$which)),
                  Pair,
                  '$!value'
                ),
                0
              )
          },
          STORE => -> $, Int() $value {
              nqp::if(
                nqp::istype($value,Failure),   # RT 128927
                $value.throw,
                nqp::if(
                  (my $raw := self.raw_hash),
                  nqp::if(                      # allocated hash
                    nqp::existskey($raw,(my $which := k.WHICH)),
                    nqp::if(                    # existing element
                      nqp::isgt_i($value,0),
                      (nqp::getattr(
                        nqp::decont(nqp::atkey($raw,$which)),
                        Pair,
                        '$!value'
                      ) = $value),
                      nqp::stmts(
                        nqp::deletekey($raw,$which),
                        0
                      )
                    ),
                    nqp::if(
                      nqp::isgt_i($value,0),
                      nqp::bindkey($raw,$which,self!PAIR(k,$value))  # new
                    )
                  ),
                  nqp::if(                      # no hash allocated yet
                    nqp::isgt_i($value,0),
                    nqp::bindkey(
                      nqp::bindattr(%!elems,Map,'$!storage',
                        nqp::create(Rakudo::Internals::IterationSet)),
                      k.WHICH,
                      self!PAIR(k,$value)
                    )
                  )
                )
              )
          }
        )
    }

#--- object creation methods
    multi method new(BagHash:_:) { nqp::create(self) }

#--- introspection methods
    method total() { Rakudo::QuantHash.BAG-TOTAL(self.raw_hash) }

    method Bag(:$view) is nodal {
        nqp::if(
          (my $raw := self.raw_hash) && nqp::elems($raw),
          nqp::p6bindattrinvres(
            nqp::create(Bag),Bag,'%!elems',
            nqp::if($view,%!elems,%!elems.clone)
          ),
          bag()
        )
    }
    method BagHash() is nodal { self }
    method Mix() is nodal {
        nqp::if(
          (my $raw := self.raw_hash) && nqp::elems($raw),
          nqp::p6bindattrinvres(nqp::create(Mix),Mix,'%!elems',%!elems.clone),
          mix()
        )
    }

#--- iterator methods

    sub proxy(Mu \iter,Mu \storage) is raw {
        # We are only sure that the key exists when the Proxy
        # is made, but we cannot be sure of its existence when
        # either the FETCH or STORE block is executed.  So we
        # still need to check for existence, and handle the case
        # where we need to (re-create) the key and value.  The
        # logic is therefore basically the same as in AT-KEY,
        # except for tests for allocated storage and .WHICH
        # processing.
        nqp::stmts(
          (my $which  := nqp::iterkey_s(iter)),
          (my $object := nqp::getattr(          # recreation
            nqp::decont(nqp::iterval(iter)),Pair,'$!key')),

          Proxy.new(
            FETCH => {
                nqp::if(
                  nqp::existskey(storage,$which),
                  nqp::getattr(
                    nqp::decont(nqp::atkey(storage,$which)),Pair,'$!value'
                  ),
                  0
                )
            },
            STORE => -> $, Int() $value {
                nqp::if(
                  nqp::istype($value,Failure),  # RT 128927
                  $value.throw,
                  nqp::if(
                    nqp::existskey(storage,$which),
                    nqp::if(                    # existing element
                      nqp::isgt_i($value,0),
                      (nqp::getattr(            # value ok
                        nqp::decont(nqp::atkey(storage,$which)),
                        Pair,
                        '$!value'
                      ) = $value),
                      nqp::stmts(               # goodbye!
                        nqp::deletekey(storage,$which),
                        0
                      )
                    ),
                    nqp::if(                    # where did it go?
                      nqp::isgt_i($value,0),
                      nqp::bindkey(storage,$which,Pair.new($object,$value))
                    )
                  )
                )
            }
          )
        )
    }

    multi method iterator(BagHash:D:) {    # also .pairs
        class :: does Rakudo::Iterator::Mappy {
            method pull-one() is raw {
                nqp::if(
                  $!iter,
                  nqp::p6bindattrinvres(
                    nqp::clone(nqp::iterval(nqp::shift($!iter))),
                    Pair,
                    '$!value',
                    proxy($!iter,$!storage)
                  ),
                  IterationEnd
                )
            }
            method push-all($target --> IterationEnd) {
                nqp::while(  # doesn't sink
                  $!iter,
                  $target.push(nqp::iterval(nqp::shift($!iter)))
                )
            }
        }.new(%!elems)
    }

    multi method values(BagHash:D:) {
        Seq.new(class :: does Rakudo::Iterator::Mappy {
            method pull-one() is raw {
                nqp::if(
                  $!iter,
                  proxy(nqp::shift($!iter),$!storage),
                  IterationEnd
                )
            }

            # same as Baggy.values
            method push-all($target --> IterationEnd) {
                nqp::while(  # doesn't sink
                  $!iter,
                  $target.push(nqp::getattr(nqp::decont(
                    nqp::iterval(nqp::shift($!iter))),Pair,'$!value'))
                )
            }
        }.new(%!elems))
    }

    multi method kv(BagHash:D:) {
        Seq.new(class :: does Rakudo::Iterator::Mappy-kv-from-pairs {
            method pull-one() is raw {
                nqp::if(
                  $!on,
                  nqp::stmts(
                    ($!on = 0),
                    proxy($!iter,$!storage)
                  ),
                  nqp::if(
                    $!iter,
                    nqp::stmts(
                      ($!on = 1),
                      nqp::getattr(
                        nqp::iterval(nqp::shift($!iter)),Pair,'$!key')
                    ),
                    IterationEnd
                  )
                )
            }
        }.new(%!elems))
    }

#---- selection methods
    multi method grab(BagHash:D:) {
        nqp::if(
          (my $raw := self.raw_hash) && nqp::elems($raw),
          nqp::stmts(
            (my $iter := Rakudo::QuantHash.BAG-ROLL($raw,self.total)),
            nqp::if(
              nqp::iseq_i(
                (my $value := nqp::getattr(nqp::iterval($iter),Pair,'$!value')),
                1
              ),
              nqp::stmts(              # going to 0, so remove
                (my $object := nqp::getattr(nqp::iterval($iter),Pair,'$!key')),
                nqp::deletekey($raw,nqp::iterkey_s($iter)),
                $object
              ),
              nqp::stmts(
                --nqp::iterval($iter).value,   # for now
#                nqp::bindattr(
#                  nqp::iterval($iter),
#                  Pair,
#                  '$!value',
#                  nqp::sub_i($value,1)
#                ),
                nqp::getattr(nqp::iterval($iter),Pair,'$!key')
              )
            )
          ),
          Nil
        )
    }
    multi method grab(BagHash:D: Callable:D $calculate) {
        self.grab( $calculate(self.total) )
    }
    multi method grab(BagHash:D: $count) {
        if nqp::istype($count,Whatever) || $count == Inf {
            my @grabbed = self!ROLLPICKGRABN(self.total,%!elems.values);
            %!elems = ();
            @grabbed;
        }
        else {
            my @grabbed = self!ROLLPICKGRABN($count,%!elems.values);
            for @grabbed {
                if %!elems.AT-KEY(.WHICH) -> $pair {
                    %!elems.DELETE-KEY(.WHICH) unless $pair.value;
                }
            }
            @grabbed;
        }
    }
}

# vim: ft=perl6 expandtab sw=4
