use v5.20;
use strict;
use warnings;
use Mojo::UserAgent;
use Mojo::DOM;
use Carp;
use Time::HiRes 'usleep';
use DBI;
use Date::Manip;
use List::Util qw<shuffle>;

binmode STDOUT, ':utf8';

my $ua = Mojo::UserAgent->new;
$| = 1;

# Site Configuration
#     http://domain.yuku.com/viewtopic.php?t=11571&start=0
my $domain         = 'domain.yuku.com';
my $api_path       = 'viewtopic.php';
# This is the path of where the database file will be created
# (If you use a relative path, you should keep running it from the same working directory)
my $db_file        = "$domain.sqlite";
# Select the topics you wish to grab.  The topic ids are part of the URL, like
#     http://domain.yuku.com/hey-guise!-t152-s60.html
# This is topic id 152, starting at post #61
my $start_topic    = 1;
my $end_topic      = 10000;
my $posts_per_page = 20;
# Or override this by asking for a list of specific thread numbers
my @get_topics     = ();
# Download the listed topics more than once, boolean
# Use this to grab topics that have had new posts since your last rip
# (which you should probably specifically identify in @get_topics, because it's not magic)
my $repeat_thread  = 0;
# optionally add a delay (in microseconds) between requests to
# prevent problems if they throttle you (download only)
my $delay          = 2_000_000;
# verbose messages during run?
my $verbose        = 1;

# The Actual program
#####################
my $root_url = "http://$domain/$api_path";

print @ARGV ? "Reading from " . scalar @ARGV . " files"
    : "Gathering data from $root_url";

my $dbh = get_db($db_file);
my %seen_users = map {$_->[0] => 1} $dbh->selectall_arrayref("SELECT username FROM users")->@*;
my %seen_threads = map {$_->[0] => 1}
    $dbh->selectall_arrayref("SELECT tid FROM threads UNION SELECT tid FROM bogusthreads UNION SELECT tid FROM unauthorized")->@*
    unless $repeat_thread;

# The main loop
if (@ARGV) {
    for my $filename (@ARGV) {
        extract_posts( Mojo::DOM->new( slurp $filename ) );
    }
} else {
    my @topic_list = scalar(@get_topics) ? @get_topics : ($start_topic .. $end_topic );
    for my $topic (shuffle @topic_list) {
        download_thread( $topic ) unless $seen_threads{$topic};
    }
}


sub download_thread {
    my ($topic, $start) = @_;
    $start //= 0;

    print "looking for thread t=$topic&start=$start";
    usleep $delay;
    my $res = $ua->get($root_url, { 'Accept' => 'text/html'}, 'form' => {
        t => $topic,
        start => $start
    })->res;

    unless ($res->is_success) {
        if ($res->code eq '404') {
            $dbh->do("INSERT OR IGNORE INTO bogusthreads VALUES (?)", undef, $topic);
            say " - 404, bogus topic";
            return undef;
        }
        else {
            confess "HTTP error: " . $res->code . ' ' . $res->message
             . ( $start ? " -- died in the middle of t=$topic\&$start=$start" : '');
        }
    }
    print " - downloaded - ";

    my $dom = $res->dom();
    if ($dom->at('#page-body .login_container')) {
        $dbh->do("INSERT OR IGNORE INTO unauthorized VALUES (?)", undef, $topic);
        say "UNAUTHORIZED THREAD";
        return undef;
    }
    my $savecount = extract_posts( $dom );
    print "$savecount saved\n";

    unless ( $start > 0 ) {
        # get thread size
        $dom->find('.pagination')->last->text =~ /(\d+) post/;
        my $postcount = $1;

        # recurse if we need more pages
        $start += $posts_per_page;
        while ( $start < $postcount ) {
            download_thread( $topic, $start );
            $start += $posts_per_page;
        }
    }

}

sub extract_posts {
    my $dom = shift;

    # Get topic information, even if we already have it
    my $title = $dom->find('.topic-title a')->[0]->text();
    my $topic_id = $dom->find('link[rel="alternate"][title^="Feed - Topic -"]')->first->attr('href');
    $topic_id =~ s|^.*?/topic/(\d+).*$|$1|s;
    my $forumid = $dom->find('#nav-breadcrumbs .crumb:last-child')->last->attr('data-forum-id');
    say $title;

    $dbh->do("INSERT OR REPLACE INTO threads (tid, forum_id, topic) VALUES (?, ?, ?)", undef,
        $topic_id, $forumid, $title);

    my $savecount = 0;
    $dom->find('.post')->each( sub {
        my $post = shift;
        my $pid = substr( $post->attr('id'), 1);

        my $count   = substr( $post->at('.author a span')->text, 1) - 1;
        my $datestr = $post->at('.author a')->text;
        my $date = ParseDateString($datestr);
        my $timestamp = UnixDate($date, '%s');

        my $author = $post->at('.avatar-username .username, .avatar-username .username-coloured')->text;

        # Tapatalk hides the post title in an link in a comment, WRYYYYYYYY . ('Y' x 40)
        my $titlecomment = $post->at('.postbody > div:first-child > h3:first-child')->child_nodes->first->content;
        my $posttitle = Mojo::DOM->new( $titlecomment )->at('a')->text;

        # were we edited?
        my $edit_count = 0;
        my ($last_editor, $edit_time);
        if (my $notice = $post->at('.notice') ) {
            my $editnotice = $notice->text();
            if ($editnotice =~ /on (\d.*?), edited (\d+)/) {
                $edit_count = $2;
                my $edate = ParseDateString($1);
                $edit_time = UnixDate($edate, '%s');
                $last_editor = $post->at('.notice .username, .notice .username-coloured')->text;
            }
        }


        my $content = $post->at('.content')->content;
        my $sig = $post->at('.signature');
        my $signature = $sig ? $post->at('.signature')->content : undef;
        $dbh->do('INSERT OR IGNORE INTO posts (pid, topic, seq, author, utime, edit_count, edit_user, edit_time, post_title, content, signature)
            VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', undef,
            $pid, $topic_id, $count, $author, $timestamp, $edit_count, $last_editor, $edit_time, $posttitle, $content, $signature
        );
        ++$savecount;

        # If we haven't seen this user yet, add her to the DB
        unless ($seen_users{$author}) {
            my $join_date = UnixDate( ParseDateString( $post->at('dd.profile-joined')->text ), "%s" );
            my $rank = $post->at('dd.profile-rank')->text;
            my $post_count = $post->at('.thread-user-detail .detail-value > a > span')->text;
            $post_count =~ s/\D//g;
            $dbh->do("INSERT INTO users (username, join_date, post_count, rank) VALUES (?, ?, ?, ?)", undef,
                $author, $join_date, $post_count, $rank
            ) or die "Couldn't insert user $author";
            $seen_users{$author} = 1;
        }
    });

    return $savecount;
}

sub get_db {
    my $db_file = shift;
    my $db_exists = -e $db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file","","");
    unless ($db_exists) {
        # Build the DB schema
        $dbh->do(q/
        CREATE TABLE threads (
            tid INT PRIMARY KEY,
            forum_id INT NOT NULL,
            topic TEXT
        )/) or die $dbh->errstr;
        $dbh->do(q/
        CREATE TABLE posts (
            pid INT PRIMARY KEY,
            topic INT NOT NULL,
            seq INT NOT NULL,
            author TEXT NOT NULL,
            utime INTEGER NOT NULL,
            edit_count INT DEFAULT 0,
            edit_user TEXT,
            edit_time INT,
            post_title TEXT,
            content TEXT,
            signature TEXT
        )/) or die $dbh->errstr;
        $dbh->do(q/
        CREATE TABLE users (
            username TEXT PRIMARY KEY,
            join_date INT NOT NULL,
            post_count INT NOT NULL,
            rank TEXT
        )/) or die $dbh->errstr;

        $dbh->do(q/
        CREATE TABLE bogusthreads (
            tid INT PRIMARY KEY
        )/) or die $dbh->errstr;

        $dbh->do(q/
        CREATE TABLE unauthorized (
            tid INT PRIMARY KEY
        )/) or die $dbh->errstr;

        # Tapatalk calls anon users 'Guest', and we don't want to look for their info so as to avoid script dying in a fire lol
        $dbh->do(q/ INSERT INTO users VALUES ('Guest', 0, 0, 'undef') /);
    }
    return $dbh;
}

# One-liner to read in an entire file in UTF-8, because why add a File::Slurp dependency
sub slurp { local $/ = undef; my $fn = shift; open my $fh, '<:encoding(UTF-8)', $fn or die "Cannot read file $fn"; my $c = <$fh>; close $fh; return $c }
