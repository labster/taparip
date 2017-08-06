use strict;
use warnings;
use v5.20;
use DBI;
use Mojo::DOM;
use List::Util qw<any reduce>;
use File::Basename qw<basename>;
use HTML::Entities;


# Config section
my $db_file = "dwforums.sqlite";
# Filter selection
# Just in case you're debugging and only want to edit part of the data
my $WHERE_CLAUSE = '';
#   my $WHERE_CLAUSE = "WHERE content LIKE '%<%'";
#   my $WHERE_CLAUSE = "WHERE content LIKE '%[link=%' ORDER by pid";
# If you're moving image files to the new site, specify the new path here
my $localhosting_image_dir = "/forumimportfiles";
# If you have a lot of links to specific sites, you can upgrade them to HTTPS links by listing the domain here
# Yes it's 2017 it should be all sites srsly.
my $upgrade_http_domains_regex = join '|', qw<
imgur.com
deviantart.com
imageshack.us
imageshack.com
gawkerassets.com
photobucket.com
bungie.net
google.com
googleusercontent.com
gstatic.com
staticflickr.com
dakkadakka.com
blogspot.com
wordpress.com
static.fimfiction.net
tumblr.com
xkcd.com
daz3d.com
nasa.gov
facdn.net
s3.amazonaws.com
wikia.nocookie.net
>;

### And that's it
######### Program content ##########
my $DECODE_ENTITIES = $ARGV[0] eq '-e';
my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file","","");

my %avail_emoji = (qw<
    :wink:    ;)
    :angel:   :angel:
    :grin:    :D
>);

$upgrade_http_domains_regex = qr/$upgrade_http_domains_regex/;

my $count = $dbh->selectall_arrayref(qq{SELECT count(*) FROM posts $WHERE_CLAUSE})->[0][0];
my $offset = 0;
my $interval = 500;
my $all_changed_count = 0;
while ( $offset < $count ) {
    my $changecount = 0;
    my $dball = $dbh->selectall_arrayref(qq{SELECT pid, content, signature FROM posts $WHERE_CLAUSE LIMIT $interval OFFSET $offset});
    
    for (@$dball) {
        my ($pid, $p, $sig) = @$_;
        my $orig = $p;
        my $sigo = $sig;

        $p = convert_content($p);
        $sig = convert_content($sig) if defined $sig;

        if ($p ne $orig or (defined $sigo and $sig ne $sigo)) {
            $changecount++;
            $dbh->do("UPDATE posts SET content = ?, signature = ? WHERE pid = ?", undef, $p, $sig, $pid);
        }
    }
    $offset += $interval;
    say "out of ", scalar @$dball, " we changed $changecount ($offset/$count)";
    $all_changed_count += $changecount;
}
say "Out of all ", $count, " we changed ", $all_changed_count;


sub convert_content {
    my $html = shift;

    email_tags ( $html );
    markup_failure_fix( $html );
    my $dom = Mojo::DOM->new( $html );

    embed_replace($dom);
    replace_tags_simple($dom, "em", "i");
    replace_tags_simple($dom, "strong", "b");
    replace_tags_simple($dom, "span[style=text-decoration: line-through;]", "s");
    replace_tags_simple($dom, "span[style=text-decoration: underline]", "u");

    list_item($dom, "li", "*");
    replace_tags_simple($dom, "ul", "list");
    replace_tags_simple($dom, "ol[style=list-style-type: lower-alpha]", "list", "a");
    replace_tags_simple($dom, "ol[style=list-style-type: decimal]", "list", "1");

    hyperlink_tags($dom);
    spoiler_tags($dom);
    code_tags($dom);
    quote_tags($dom);
    image_tags($dom);
    remove_tag($dom, 'tbody');
    replace_tags_simple($dom, '.post_content_table tr', 'tr');
    replace_tags_simple($dom, '.post_content_table td', 'td');
    replace_tags_simple($dom, 'table.post_content_table', 'table');

    hr_replace($dom);
    style_spans($dom);
    style_spans($dom);

    align_tags($dom);
    # need to remove entities here
    $html = $dom->to_string;
    $html =~ s/<br>\n*/\n/g;
    $html = decode_entities($html) if $DECODE_ENTITIES;
    return $html;
}


sub email_tags {
    $_[0] =~ s|<a href="[^"]+"><span class="__cf_email__" data-cfemail="([a-f0-9]+)">\[email protected\]</span><script.*?</script></a>|unmask_email($1)|eg;
    $_[0] =~ s|<a class="__cf_email__" data-cfemail="([a-f0-9]+)" href="[^"]+">\[email protected\]</a><script.*?</script>|unmask_email($1)|eg;
    $_[0] =~ s|<span class="__cf_email__" data-cfemail="([a-f0-9]+)">\[email protected\]</span><script.*?</script>|unmask_email($1)|eg;
    $_[0] =~ s|<a href="/cdn-cgi/l/email-protection#[0-9a-f]+">([^<]+)</a>|$1|g;
}

sub unmask_email {
    my @hex_array = map hex, unpack("(A2)*", shift);
    my $mask = shift @hex_array;
    return join '', map chr( $_ ^ $mask ), @hex_array;
}

sub align_tags {
    my $dom = shift;

    $dom->find( 'div[align]' )->each(  sub {
        my $d = shift;
        my $innerHTML = $d->content();
        my $alignment = $d->attr('align');
        die unless 'align';
        $d->replace("[align=$alignment]${innerHTML}[/align]")
    });
}

sub replace_tags_simple {
    my ($dom, $selector, $bbtag, $param) = @_;
    $param = defined $param ? "=$param" : '';
    $dom->find( $selector )->each( sub {
        my $d = shift;
        $d->replace( "[$bbtag$param]" . $d->content . "[/$bbtag]" );
    });
}

sub remove_tag {
    my ($dom, $selector) = @_;
    # Removes the tag, not its content
    $dom->find( $selector )->each( sub {
        my $d = shift;
        $d->replace( $d->content );
    });
}

sub hr_replace {
    my $dom = shift;
    #This one is unitary, so we can't make a pair
    $dom->find('hr')->each( sub { shift->replace("[hr]"); } );
}

sub style_spans {
    my $dom = shift;
    $dom->find( 'span[style]' )->sort(
        sub { $b->ancestors->size <=> $a->ancestors->size }  #depth first - paranoia
    )->each( sub {
        my $d = shift;
        # style attribute only
        return unless scalar keys %$d == 1;
        my $style = $d->attr('style');
        if ($style =~ /^color:\s*([^;]+);?/) {
            $d->replace("[color=$1]" . $d->content . "[/color]");
        }
        elsif ($style =~ /^font-size: (\d+)(?:px)?%; line-height: normal;?$/) {
            my $pct   = $1;
            my %sizes = (
                10 => "xx-small",
                50 => "x-small",
                75 => "small",
                100 => "medium",
                120 => "large",
                140 => "x-large",
                180 => "xx-large",
                15 => "medium",     # because some values were "15px%" :/
                16 => "xx-small",   # for calculations
                14 => "xx-small",
            );
            # get the exact size, or choose the closest value
            my $size = $sizes{$pct} //
                $sizes{ reduce { abs($a - $pct) < abs($b - $pct) ? $a : $b } keys %sizes };
            $d->replace("[size=$size]" . $d->content . "[/size]");
        }
        elsif ($style =~ /^font-family: ([^;]+);?$/) {
            $d->replace("[font=$1]" . $d->content . "[/font]");
        }
    });
}

sub list_item {
    my $dom = shift;
    $dom->find('ul, ol')->each( sub {
        my $d = shift;
        my $x = $d->content;
        $x =~ s|<li>(.*?)</li>\n*|[*]$1\n|sg;
        $x =~ s|^\s*|\n|;
        $d->content( $x );
    });
}

sub code_tags {
    my $dom = shift;

    $dom->find( 'div.codebox' )->each(  sub {
        my $d = shift;
        my $content = $d->at('code')->content();
        $d->replace("[code]${content}[/code]")
    });
}

sub quote_tags {
    my $dom = shift;
    $dom->find('blockquote > div > cite')->sort(
        sub { $b->ancestors->size <=> $a->ancestors->size }  #depth first - necessary!
    )->each( sub {
        my $d = shift;
        my $author = $d->text;
        $author =~ s/\s+wrote:$//;
        my $bq = $d->parent->parent;
        $d->remove;
        my $content = $bq->at('div')->content;
        $bq->replace("[quote=$author]${content}[/quote]");
    });
    $dom->find('blockquote.uncited')->each( sub {
        my $d = shift;
        $d->replace("[quote]" . $d->at('div')->content . "[/quote]" );
    });
}

sub spoiler_tags {
    my $dom = shift;

    $dom->find( 'dl.codebox' )->each(  sub {
        my $d = shift;
        my $content = $d->at('dd')->content();
        $d->replace("[spoiler]${content}[/spoiler]")
    });
}

sub hyperlink_tags {
    my $dom = shift;

    $dom->find( 'a.postlink' )->each(  sub {
        my $d = shift;
        my $content = $d->content();
        my $href= $d->attr('href');
        $d->replace("[url=$href]${content}[/url]")
    });
}

sub image_tags {
    my $dom = shift;
    $dom->find( 'img' )->each( sub {
        my $d = shift;
        my $class = $d->attr('class');
        if ($class eq 'postimage') {
            my $url = $d->attr('src');
            $url =~ s/^imageproxy\.php\?url=//;
            if ($url =~ m|/images.yuku.com/| and $localhosting_image_dir) {
                $url = $localhosting_image_dir . basename($url);
            }
            elsif ($url =~ m|^http://([^\/]+)| ) {
                $url =~ s/^http:/https:/ if $url =~ $upgrade_http_domains_regex;
            }
            $d->replace("[img]" . $url . "[/img]");
        }
        elsif ($class eq 'smilies') {
            #<img alt=":)" class="smilies" height="0" src="./forum_data/forums.dr/drun/drunkardswalkforums/smilies/92.gif" title="banana dance" width="0">
            # only case, so we already know the URL:
            $d->replace("[img]$localhosting_image_dir/banana-dance.gif[/img]")
        }
        elsif ($class eq 'emoji') {
            my $alt = $d->attr('alt');
            if ($avail_emoji{$alt}) {
                $d->replace( $avail_emoji{$alt} );
            }
            elsif ( $d->attr('src') =~ m|/([0-9a-f]+)\.svg$| ){
                # calculate the codepoint
                $d->replace( chr hex $1 );
            }
            else {
                # just insert the emoji
                $d->replace( $alt );
            }
        }
        else {
            die "don't know how to deal with class $class.";
        }
    });
}

sub embed_replace {
    my $dom = shift;
    my @supported_videos = qw<youtube vimeo twitch liveleak dailymotion metacafe facebook veoh >;

    $dom->find('div[data-s9e-mediaembed]')->each( sub {
        my $d = shift;
        my $type = $d->attr('data-s9e-mediaembed');

        if (any { $type eq $_ } @supported_videos) {
            $d->replace("[video=$type]" . $d->at('iframe')->attr('src') . "[/video]");
        }
        else {
            $d->replace("[url]" . $d->at('iframe')->attr('src') . "[/url]");
        }
    });
    my %urls_by_site = (
        'tumblr' => 'https://embed.tumblr.com/embed/post/',
        'imgur'  => 'https://imgur.com/',
        'reddit' => 'https://reddit.com/',
        'twitter' => 'https://twitter.com/user/status/',
        'facebook' => 'https://www.facebook.com/user/posts/',
        'instagram' => 'https://instagram.com/p/',
    );
    $dom->find('iframe[data-s9e-mediaembed]')->each( sub {
        my $d = shift;
        my $site = $d->attr('data-s9e-mediaembed');
        my $src  = $d->attr('src');
        if ($urls_by_site{$site}) {
            my $hash = $src =~ s/^.*?#//r;  # think window.location.hash
            $d->replace("[url]$urls_by_site{$site}$hash\[/url]");
        }
        else {
            $d->replace("[url]$src\[/url]");
        }
    });        
}



# The black magick part, unfortunately, because this is more about fixing things that weren't included in the HTML like they should be
sub markup_failure_fix {
    $_[0] =~ s|\[link=<a class="postlink" href="([^"]*)">(.*?)</a>\](.*?)\[/link\]| $2 ? "[url=$1]$2\[/url]" : "[url]$1\[/url]"|eg;
    $_[0] =~ s|\[link\=\<div\ data\-s9e\-mediaembed\=\"amazon\"\ style\=\"display\:inline\-block\;width\:100\%\;max\-width\:120px\"\>\<div\ style\=\"overflow\:hidden\;position\:relative\;padding\-bottom\:200\%\"\>\<iframe\ allowfullscreen\=\"\"\ scrolling\=\"no\"\ src\=\"\/\/ws\-na\.amazon\-adsystem\.com\/widgets\/q\?ServiceVersion\=20070822\&amp\;OneJS\=1\&amp\;Operation\=GetAdHtml\&amp\;MarketPlace\=US\&amp\;ad_type\=product_link\&amp\;tracking_id\=_\&amp\;marketplace\=amazon\&amp\;region\=US\&amp\;asins\=(\w+)\&amp\;show_border\=true\&amp\;link_opens_in_new_window\=true\"\ style\=\"border\:0\;height\:100\%\;left\:0\;position\:absolute\;width\:100\%\"\>\<\/iframe\>\<\/div\>\<\/div\>(.*?)\[\/link\]| $2 ? "[url=https://www.amazon.com/foo/dp/$1/]$2\[/url]" : "[url]https://www.amazon.com/foo/dp/$1/\[/url]"|eg;
    $_[0] =~ s#\[link\=\<div\ data\-s9e\-mediaembed\=\"(?:flickr|kickstarter|youtube|liveleak|cnn|cnnmoney|liveleak|indiegogo|funnyordie|dailymotion|npr)\"[^>]*>\<div[^>]*\>\<iframe.*?src\=\"([^"]+)\"[^>]*\>\<\/iframe\>\<\/div\>\<\/div\>(.*?)\[\/link\]#  $2 ? "[url=$1]$2\[/url]" : "[url]$1\[/url]"#eg;
    $_[0] =~ s#\[link\=\<iframe allowfullscreen="" data-s9e-mediaembed="steamstore"[^>]*src\=\"//store.steampowered.com/widget/(\d+/?)\"[^>]*\>\<\/iframe\>(.*?)\[\/link\]#  $2 ? "[url=//store.steampowered.com/app/$1]$2\[/url]" : "[url]//store.steampowered.com/app/$1\[/url]"#eg;

    my %urls_by_site = (
        'tumblr' => 'https://embed.tumblr.com/embed/post/',
        'imgur'  => 'https://imgur.com/',
        'reddit' => 'https://reddit.com/',
        'twitter' => 'https://twitter.com/user/status/',
        'facebook' => 'https://www.facebook.com/user/posts/',
        'instagram' => 'https://instagram.com/p/',
    );
    $_[0] =~ s#\[link\=\<iframe allowfullscreen="" data-s9e-mediaembed="(tumblr|imgur|reddit|twitter|facebook|instagram)"[^>]*src\=\"https://s9e.github\.io/[^\#]+\#([^"]+)\"[^>]*\>\<\/iframe\>(.*?)\[\/link\]#  $3 ? "[url=$urls_by_site{$1}$2]$3\[/url]" : "[url]$urls_by_site{$1}$2\[/url]"#eg;

    $_[0] =~ s#\[link\=\<iframe allowfullscreen="" data-s9e-mediaembed="npr"[^>]*src\=\"([^"]+)\"[^>]*\>\<\/iframe\>(.*?)\[\/link\]#  $2 ? "[url=$1]$2\[/url]" : "[url]$1\[/url]"#eg;
    $_[0] =~ s#\[link\=\<div\ data\-s9e\-mediaembed\=\"(?:flickr|kickstarter|youtube|liveleak|cnn|cnnmoney|liveleak|indiegogo|funnyordie|dailymotion|npr)\"[^>]*>\<div[^>]*\>\<iframe.*?src\=\"([^"]+)\"[^>]*\>\<\/iframe\>\<\/div\>\<\/div\>(.*?)\[\/link\]#  $2 ? "[url=$1]$2\[/url]" : "[url]$1\[/url]"#eg;

    # I think this is the result of a bug, but I don't know where...
    $_[0] =~ s/\[link= \[url= ([^\]]+) \]  [^\[\]]+ \[\/url\]\s*\#* \]  ([^\[]+) \[\/link\]/\[url=$1\]$2\[\/url]/gx;
    $_[0] =~ s|\[link(=[^<\[\]\>]+\]\[\w+\][^\<\[\]\>]+\[\/\w+\]\[\/)link\]|[url${1}url]}|g;
}

