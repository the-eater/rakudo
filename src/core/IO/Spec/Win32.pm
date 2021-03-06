my class IO::Spec::Win32 is IO::Spec::Unix {

    # Some regexes we use for path splitting
    my $slash       = regex {  <[\/ \\]> }
    my $notslash    = regex { <-[\/ \\]> }
    my $driveletter = regex { <[A..Z a..z]> ':' }
    my $UNCpath     = regex { [<$slash> ** 2] <$notslash>+  <$slash>  [<$notslash>+ | $] }
    my $volume_rx   = regex { <$driveletter> | <$UNCpath> }

    method canonpath ($patharg, :$parent) {
        my $path = $patharg.Str;
        $path eq '' ?? '' !! self!canon-cat($path, :$parent);
    }

    method catdir(*@dirs) {
        return "" unless @dirs;
        return self!canon-cat( "\\", @dirs ) if @dirs[0] eq "";
        self!canon-cat(|@dirs);
    }

    # NOTE: IO::Path.resolve assumes dir sep is 1 char
    method dir-sep        { '\\' }
    method splitdir($dir) { $dir.split($slash)  }
    method devnull        { 'nul'               }
    method rootdir        { '\\'                }

    method basename(\path) {
        my str $str = nqp::unbox_s(path);
        my int $indexf = nqp::rindex($str,'/');
        my int $indexb = nqp::rindex($str,'\\');
        nqp::p6bool($indexf == -1 && $indexb == -1)
          ?? path
          !! $indexf > $indexb
             ?? substr(path,nqp::box_i($indexf + 1,Int) )
             !! substr(path,nqp::box_i($indexb + 1,Int) );
    }

    method tmpdir {
        my $ENV := %*ENV;
        my $io;
        first( {
            if .defined {
                $io = .IO;
                $io.d && $io.r && $io.w && $io.x;
            }
        },
          $ENV<TMPDIR>,
          $ENV<TEMP>,
          $ENV<TMP>,
          'SYS:/temp',
          'C:\system\temp',
          'C:/temp',
          '/tmp',
          '/',
        ) ?? $io !! IO::Path.new(".");
    }

    method path {
       (".",
         split(';', %*ENV<PATH> // %*ENV<Path> // '').map( {
           .subst(:global, q/"/, '') } ).grep: *.chars );
   }

    method is-absolute ($path) {
        nqp::p6bool(
          nqp::iseq_i(($_ := nqp::ord($path)), 92) # /^ ｢\｣ /
          || nqp::iseq_i($_, 47)                   # /^ ｢/｣ /
          || (nqp::eqat($path, ':', 1) # /^ <[A..Z a..z]> ':' [ ｢\｣ | ｢/｣ ] /
              && ( (nqp::isge_i($_, 65) && nqp::isle_i($_, 90)) # drive letter
                || (nqp::isge_i($_, 97) && nqp::isle_i($_, 122)))
              && ( nqp::iseq_i(($_ := nqp::ordat($path, 2)), 92) # slash
                || nqp::iseq_i($_, 47))))
    }

    multi method split(IO::Spec::Win32: Cool:D $path is copy) {
        $path ~~ s[ <$slash>+ $] = ''                       #=
            unless $path ~~ /^ <$driveletter>? <$slash>+ $/;

        $path ~~
            m/^ ( <$volume_rx> ? )
            ( [ .* <$slash> ]? )
            (.*)
             /;

        my str $volume   = $0.Str;
        my str $dirname  = $1.Str;
        my str $basename = $2.Str;

        nqp::stmts(
          nqp::while( # s/ <?after .> <$slash>+ $//
            nqp::isgt_i(($_ := nqp::sub_i(nqp::chars($dirname), 1)), 0)
            && (nqp::eqat($dirname, ｢\｣, $_) || nqp::eqat($dirname, '/', $_)),
            $dirname = nqp::substr($dirname, 0, $_)),
          nqp::if(
            $volume && nqp::isfalse($dirname) && nqp::isfalse($basename),
            nqp::if(
              nqp::eqat($volume, ':', 1) # /^ <[A..Z a..z]> ':'/
                && ( (nqp::isge_i(($_ := nqp::ord($volume)), 65) # drive letter
                    && nqp::isle_i($_, 90))
                  || (nqp::isge_i($_, 97) && nqp::isle_i($_, 122))),
              ($dirname = '.'),
              ($dirname = ｢\｣))),
          nqp::if(
            (nqp::iseq_s($dirname, ｢\｣) || nqp::iseq_s($dirname, '/'))
            && nqp::isfalse($basename),
            $basename = ｢\｣),
          nqp::if(
            $basename && nqp::isfalse($dirname),
            $dirname = '.'));

        (:$volume, :$dirname, :$basename, :directory($dirname))
    }

    method join ($volume, $dirname is copy, $file is copy) {
        $dirname = '' if $dirname eq '.' && $file.chars;
        if $dirname.match( /^<$slash>$/ ) && $file.match( /^<$slash>$/ ) {
            $file    = '';
            $dirname = '' if $volume.chars > 2; #i.e. UNC path
        }
        self.catpath($volume, $dirname, $file);
    }

    method splitpath(Str() $path, :$nofile = False) {

        if $nofile {
            $path ~~ /^ (<$volume_rx>?) (.*) /;
            (~$0, ~$1, '');
        }
        else {
            $path ~~
                m/^ ( <$volume_rx> ? )
                ( [ .* <$slash> [ '.' ** 1..2 $]? ]? )
                (.*)
                 /;
            (~$0, ~$1, ~$2);
        }
    }

    method catpath($volume is copy, $dirname, $file) {

        # Make sure the glue separator is present
        # unless it's a relative path like A:foo.txt
        if $volume.chars and $dirname.chars
           and $volume !~~ /^<$driveletter>/
           and $volume !~~ /<$slash> $/
           and $dirname !~~ /^ <$slash>/
            { $volume ~= '\\' }
        if $file.chars and $dirname.chars
           and $dirname !~~ /<$slash> $/
            { $volume ~ $dirname ~ '\\' ~ $file; }
        else     { $volume ~ $dirname     ~    $file; }
    }

    method rel2abs ($path is copy, $base? is copy, :$omit-volume) {

        my $is_abs = ($path ~~ /^ [<$driveletter> <$slash> | <$UNCpath>]/ && 2)
                  || ($path ~~ /^ <$slash> / && 1)
                  || 0;

        # Check for volume (should probably document the '2' thing...)
        return self.canonpath( $path ) if $is_abs == 2 || ($is_abs == 1 && $omit-volume);

        if $is_abs {
            # It's missing a volume, add one
            my $vol;
            $vol = self.splitpath($base)[0] if $base.defined;
            $vol ||= self.splitpath($*CWD)[0];
            return self.canonpath( $vol ~ $path );
        }

        if not defined $base {
        # TODO: implement _getdcwd call ( Windows maintains separate CWD for each volume )
        # See: http://msdn.microsoft.com/en-us/library/1e5zwe0c%28v=vs.80%29.aspx
            #$base = Cwd::getdcwd( (self.splitpath: $path)[0] ) if defined &Cwd::getdcwd ;
            #$base //= $*CWD ;
            $base = $*CWD;
        }
        elsif ( !self.is-absolute( $base ) ) {
            $base = self.rel2abs( $base );
        }
        else {
            $base = self.canonpath( $base );
        }

        my ($path_directories, $path_file) = self.splitpath( $path )[1..2] ;

        my ($base_volume, $base_directories) = self.splitpath( $base, :nofile ) ;

        $path = self.catpath(
                    $base_volume,
                    self.catdir( $base_directories, $path_directories ),
                    $path_file
                    ) ;

        return self.canonpath( $path ) ;
    }


    method !canon-cat ( $first, *@rest, :$parent --> Str:D) {
        $first ~~ /^ ([   <$driveletter> <$slash>?
                        | <$UNCpath>
                        | [<$slash> ** 2] <$notslash>+
                        | <$slash> ]?)
                       (.*)
                   /;
        my str $volume = ~$0;
        my str $path   = ~$1;
        my int $temp;


        $volume = nqp::join(｢\｣, nqp::split('/', $volume));
        $temp   = nqp::ord($volume);

        nqp::if(
          nqp::eqat($volume, ':', 1) # this chunk == ~~ /^<[A..Z a..z]>':'/
            && ( (nqp::isge_i($temp, 65) && nqp::isle_i($temp, 90))
              || (nqp::isge_i($temp, 97) && nqp::isle_i($temp, 122))),
          ($volume = nqp::uc($volume)),
          nqp::if(
            ($temp = nqp::chars($volume))
              && nqp::isfalse(nqp::eqat($volume, ｢\｣, nqp::sub_i($temp, 1))),
            ($volume = nqp::concat($volume, ｢\｣))));

        $path = join ｢\｣, $path, @rest.flat;

        # /xx\\\yy\/zz  --> \xx\yy\zz
        $path = nqp::join(｢\｣, nqp::split('/', $path));
        nqp::while(
          nqp::isne_i(-1, $temp = nqp::index($path, ｢\\｣)),
          ($path = nqp::replace($path, $temp, 2, ｢\｣)));

        # xx/././yy --> xx/yy
        $path ~~ s:g/[ ^ | ｢\｣]   '.'  ｢\.｣*  [ ｢\｣ | $ ]/\\/;

        nqp::if($parent,
          nqp::while(
            ($path ~~ s:g {
                [^ | <?after ｢\｣>] <!before ｢..\｣> <-[\\]>+ ｢\..｣ [ ｢\｣ | $ ]
              } = ''),
            nqp::null));

        nqp::while( # \xx --> xx  NOTE: this is *not* root
          nqp::iseq_i(0, nqp::index($path, ｢\｣)),
          ($path = nqp::substr($path, 1)));

        nqp::while( # xx\ --> xx
          nqp::eqat($path, ｢\｣, ($temp = nqp::sub_i(nqp::chars($path), 1))),
          ($path = nqp::substr($path, 0, $temp)));

        nqp::if( # <vol>\.. --> <vol>\
          nqp::eqat($volume, ｢\｣, nqp::sub_i(nqp::chars($volume), 1)),
          $path ~~ s/ ^  '..'  ｢\..｣*  [ ｢\｣ | $ ] //);

        nqp::if(
          $path,
          nqp::concat($volume, $path),
          nqp::stmts( # \\HOST\SHARE\ --> \\HOST\SHARE
            nqp::iseq_i(0, nqp::index($volume, ｢\\｣))
                && nqp::iseq_i(nqp::rindex($volume, ｢\｣),
                  ($temp = nqp::sub_i(nqp::chars($volume), 1)))
                && ($volume = nqp::substr($volume, 0, $temp)),
            $volume || '.'))
    }
}

# vim: ft=perl6 expandtab sw=4
