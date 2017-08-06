# Conversion tools
Well, tool, because currently there's only one of them, and it only does syntax.

## Language support

The dude I wrote this for wanted to make a forum in MyBB, so this changes it to MyCode.  If you want something else like BBcode or whatever, it should be readable enough that you just change the output tag for each subroutine.  Well, ask me in 6 months about the readable part.  At least it's not a giant mass of regexes.

## Configuration for html2mybb.pl

Change the value of `$db_file` in the code to the path of your sqlite database created by `taparip.pl`.  You may want to change some of the other stuff there too, but there's not much to do here.

Make a copy of your DB file, just in case something goes pear-shaped.  It didn't for me, but it was nice to be able to look back and verify that no I didn't cause posts to explode.

## Usage

Run `perl html2mybb.pl`.  *Repeatedly*.

(I'm using an HTML parser, but because I'm not doing the changes depth-first, elements might be removed from the DOM before they get a chance to be changed.  I could maybe fix, but my project is done so there's no reason me to improve it now.)

After 5 or 6 times of running the script, it should eventually tell you that there were 0 changes made.  When that happens, run one final time with the `-e` switch:

        perl html2mybb.pl -e

This will decode the HTML entities as a final step.  You don't want to do this until you know for sure all of the HTML tags are replaced with BBcode tags.

## Known bugs

Can't fix all of the mistakes caused by [phpbb-ext-mediaembed](https://github.com/s9e/phpbb-ext-mediaembed) inserting itself into links, sorry.  I got tired of writing regexes when I was down to 100ish broken posts so I quit lol.

Should either do depth-first replacements, or rebuild the DOM after each change, or replace all the code with unreadable and probably wrong regexes.  One of those anyway.  Or be lazy and just call `convert_content` until it stops changing.  Workaround of running the script multiple times seems to be acceptable.

## Author

Brent Laabs <bslaabs@gmail.com>

## License

MIT License