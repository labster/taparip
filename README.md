# taparip
Rip threads from a Tapatalk forum into a Sqlite3 database

## What is this, then

Tapatalk recently took over Yuku, which, while it had it's problems,
still looked like a proper PHPBB host.  Then came Tapatalk, with its
promises of being mobile friendly, which of course means "modern UX
with MOAR WHITESPACE and gray-on-gray", hiding tons of details from
users, 33 external stylesheets, 18 external JS files, and 5 tons of
flax.

If you feel like moving on from such amazing software, you are (not)
alone.  This is a way to extract the HTML content of each forum post
into a Sqlite database.  Each post's content, sig, and metadata are
stored separately, on the assumption that you're going to do something
to move it into another forum.  It might be on different software, but
at least you have a DB to keep it organized, right?

Or are you just put off by the constant stream of 503s and 99 luftbaloon
error messages?  Do you want a backup of your forum in case it hits the
fan yet again?  This software also for you.

## Requirements
* Perl 5.20 or higher.  Mainly because I like postfix dereferencing.  If you need a lower version I'll grudgingly take it out.  But also consider [Perlbrew](https://perlbrew.pl/) to get a new version, which can also build cpanm easily.
* [Sqlite 3](http://sqlite.org/download.html) is probably already installed on your system if you're considering this
* A few perl modules from CPAN.  If you have `cpanm` installed, just do: `cpanm Mojo::UserAgent Carp DBI Date::Manip`.  Seriously Mojolicious' Mojo::DOM is great, I learned a lot from this project.
* A sense of wonder and adventure

## Configuration

Read the first part of the file `taparip.pl`.  You'll need to specify
the URL of your site, where you want to save your database, what thread
ids you want to download, as a list or range.  There's some more stuff,
but it's documented in the file.

## Execution

`perl taparip.pl`

Will download and rip from the forum based on the configuration you
provided above, and fill the data into the database.
Many painless, much simple wow.

`perl taparip.pl thread1.html thread2.html ...`

Instead of downloading, this will just extract the data from files
you've already downloaded.  If someone has already ripped the forum
with other software, this is probably the way to go.

## What's ripped, what's not

This only grabs textual content of threads, along with its sigs.  It's
in HTML format, not PHPBB format.  Anything that's metadata about the
posts or threads gets saved -- post time, number of times edited, author,
thread, forum, etc.

Images and avatars are not downloaded.  While each thread gets a forum ID,
it does not save the names of forums.  Nor does it gather thread-level
information like last edited/posted, but hey, you can calculate that
yourself from the post data.  That's why I gave you the data in an RDBMS.

## Is this 100% legal?

Well... OK, the Tapatalk ToS say that you are not allowed to harvest or
scrape data from their website for any purpose not expressly allowed by them.
They then state that you are solely responsible for backing up data, and
WE ARE ALLCAPS TOTES INDEMNIFIED IF WE LOSE ANYTHING BECAUSE
IT'S ALL UP TO YOU.
Anyway IANAL so this is not legal advice but it sounds
to me like they are expressly allowing it for backup purposes.  Also it's not
like they have a robots.txt that matches what their ToS says.  Also also
did you agree to these terms when you signed up for Yuku?  Probably not.
(Terms of Service: They make me violate them, no matter who they are.)

## Author

Brent Laabs <bslaabs@gmail.com>

## License

MIT License

## Terms of Service

By using taparip, hereafter "the software", you agree to eat one (1) cookie.
