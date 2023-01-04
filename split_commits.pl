#!/usr/bin/perl
# Split commits in GIT repository which contains
# files by specified path and branch
# Vitaly Chekryzhev <13hakta@gmail.com>, 2023

if ($#ARGV > -1) {
    $search_path = $ARGV[0];

    if ($#ARGV > 0) {
        $branch = $ARGV[1];
    } else {
        $branch = 'main';
    }
} else {
    print "split_commits.pl search_path [branch]\n";
    exit;
}

$message_suffix = 'split';
$command_length = 120;
$editor = "./todo_editor.sh";
$splitter = "./splitter.sh";

# All commits
@commits = split("\n", `git --no-pager log --pretty=oneline`);
@commits = reverse(@commits);

@edit_commits = ();
@commands = ();

# Create editor for interactive command updater
sub create_replacer {
    my $commitsRef = shift;
    my $filename = shift;

    open(FH, '>', $filename) or die $!;
    print FH "#!/bin/sh\n\nsed -i.bak \\\n";

    foreach $commit (@$commitsRef) {
        print FH "\t-e 's/pick \\($commit\\)/edit \\1/' \\\n";
    }

    print FH "\t\$1\n";
    close(FH);
}

# Split long strings to smaller chunks
sub get_strings {
    my ($listRef, $filter_mode, $max_len) = @_;

    my @strings = ();
    my $s = "";
    my $len = 0;

    foreach $filerec (@$listRef) {
        my ($filename, $file_mode) = @$filerec;

        next if $file_mode != $filter_mode;

        $name_len = length($filename);

        if ($len + $name_len + 1 > $max_len) {
            push(@strings, $s);

            $s = "";
            $len = 0;
        }

        $s .= " $filename";
        $len += $name_len;
    }

    if ($s ne '') { push(@strings, $s); }

    return @strings;
}

foreach (@commits) {
    ($hash, $name) = split(" ", $_, 2);

    # Files in commit
    @files = split("\n", `git show --name-status --pretty="format:" $hash`);

    @files_combined = ();
    @files_separate = ();
    @files_rest = ();

    foreach $file_rec (@files) {
        my ($mode, $name, $a, $name2) = $file_rec =~ /^(\w+)\s+([^\s]+)(\s+([^\s]+))?/;

        if ($mode eq 'D') {
            push(@files_combined, [$name, 0]);
            next;
        }

        if (substr($mode, 0, 1) eq 'R') {
            push(@files_combined, [$name, 0]);
            push(@files_combined, [$name2, 1]);
            next;
        }

        push(@files_combined, [$name, 1]);
    };

    foreach $file_ref (@files_combined) {
        @file = @$file_ref;

        if (rindex($file[0], $search_path, 0) == 0) {
            push(@files_separate, $file_ref);
        } else {
            push(@files_rest, $file_ref);
        }
    }

    if (($#files_separate > -1) && ($#files_rest > -1)) {
        $have_original_data = false;
        $have_additional_data = false;
        $short_hash = substr($hash, 0, 7);
        push(@edit_commits, $short_hash);

        push(@commands, "echo -e \\\\u001b[33m$short_hash: $name\\\\u001b[0m");
        push(@commands, "git reset HEAD~");

        @files_chunks = get_strings(\@files_rest, 1, $command_length);
        if (length(@files_chunks) > 0) {
            $have_original_data = true;
            foreach $chunk (@files_chunks) { push(@commands, "git add$chunk"); }
        }

        @files_chunks = get_strings(\@files_rest, 0, $command_length);
        if (length(@files_chunks) > 0) {
            $have_original_data = true;
            foreach $chunk (@files_chunks) { push(@commands, "git rm$chunk"); }
        }

        push(@commands, "git commit -m '$name'\n") if ($have_original_data);

        @files_chunks = get_strings(\@files_separate, 1, $command_length);
        if (length(@files_chunks) > 0) {
            $have_additional_data = true;
            foreach $chunk (@files_chunks) { push(@commands, "git add$chunk"); }
        }

        @files_chunks = get_strings(\@files_separate, 0, $command_length);
        if (length(@files_chunks) > 0) {
            $have_additional_data = true;
            foreach $chunk (@files_chunks) { push(@commands, "git rm$chunk"); }
        }

        push(@commands, "git commit -m '$name $message_suffix'") if ($have_additional_data);
        push(@commands, "git rebase --continue || exit 1\n\n");
    }
}

create_replacer(\@edit_commits, $editor);

# Write commands
open(FH, '>', $splitter) or die $!;
print FH "export PRE_COMMIT_ALLOW_NO_CONFIG=1\n";
print FH "GIT_EDITOR=$replacer git rebase --interactive --root $branch\n\n";
print FH join("\n", @commands);
close(FH);

# Make scripts executable
`chmod +x $editor`;
`chmod +x $splitter`;
