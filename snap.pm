# Snap.pm
# by Jim Smyser
# Copyright (C) 1996-2000 by Jim Smyser & USC/ISI
# $Id: Snap.pm,v 2.05 2000/04/04 09:51:03 jims Exp $
#
# Complete copyright notice follows below.
#


package WWW::Search::Snap;

=head1 NAME

WWW::Search::Snap - class for searching Snap.com! 


=head1 SYNOPSIS

    require WWW::Search;
    $search = new WWW::Search('Snap');

=head1 DESCRIPTION

Class specialization of WWW::Search for searching F<http://snap.com>.
Snap.com can return up to 1000 hits.

This class exports no public interface; all interaction should
be done through WWW::Search objects.

=head1 OPTIONS

Some options for modifying a search

=item   {'KM' => 'a'}
All the words

=item   {'KM' => 'b'}
Boolean Search

=item   {'KM' => 'o'}
Any of the words

=item   {'KM' => 't'}
Searches Title only

=item   {'KM' => 's'}
All forms of the words

=head1 SEE ALSO

To make new back-ends, see L<WWW::Search>,
or the specialized AltaVista searches described in options.

=head1 HOW DOES IT WORK?

C<native_setup_search> is called before we do anything.
It initializes our private variables (which all begin with underscores)
and sets up a URL to the first results page in C<{_next_url}>.

C<native_retrieve_some> is called (from C<WWW::Search::retrieve_some>)
whenever more hits are needed.  It calls the LWP library
to fetch the page specified by C<{_next_url}>.
It parses this page, appending any search hits it finds to 
C<{cache}>.  If it finds a ``next'' button in the text,
it sets C<{_next_url}> to point to the page for the next
set of results, otherwise it sets it to undef to indicate we're done.

=head1 AUTHOR

C<WWW::Search::Snap> is written and maintained
by Jim Smyser - <jsmyser@bigfoot.com>.

=head1 COPYRIGHT

Copyright (c) 1996-1998 University of Southern California.
All rights reserved.                                            
                                                               
Redistribution and use in source and binary forms are permitted
provided that the above copyright notice and this paragraph are
duplicated in all such forms and that any documentation, advertising
materials, and other materials related to such distribution and use
acknowledge that the software was developed by the University of
Southern California, Information Sciences Institute.  The name of the
University may not be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.


=cut
#'

#####################################################################
require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
@ISA = qw(WWW::Search Exporter);
$VERSION = '2.05';

$MAINTAINER = 'Jim Smyser <jsmyser@bigfoot.com>';
$TEST_CASES = <<"ENDTESTCASES";
&test('Snap', '$MAINTAINER', 'zero', \$bogus_query, \$TEST_EXACTLY);
&test('Snap', '$MAINTAINER', 'hic'.'kman', \$TEST_RANGE, 2,60);
&test('Snap', '$MAINTAINER', 'two', 'Bos'.'sk', \$TEST_GREATER_THAN, 101);
ENDTESTCASES

use Carp ();
use WWW::Search(qw(generic_option strip_tags));
use URI::Escape;

require WWW::SearchResult;

sub native_setup_search {
   my($self, $native_query, $native_options_ref) = @_;
   $self->{_debug} = $native_options_ref->{'search_debug'};
   $self->{_debug} = 2 if ($native_options_ref->{'search_parse_debug'});
   $self->{_debug} = 0 if (!defined($self->{_debug}));

   #Define default number of hit per page
   $self->{'_hits_per_page'} = 50;
   $self->{agent_e_mail} = 'jsmyser@bigfoot.com';
   $self->user_agent('user');
   $self->{_next_to_retrieve} = 0;

   if (!defined($self->{_options})) {
     $self->{'search_base_url'} = 'http://home.snap.com/';
     $self->{_options} = {
         'search_url' => 'http://home.snap.com/search/power/results/1,180,home-0,00.html',
           'KM' => 'a', 
           'KW' =>  $native_query,
           'AM0' => 'm',
           'AT0' => 'w',
           'AN' => '1',
           'NR' => $self->{'_hits_per_page'},
           'FR' => 'f',
           'PL' => 'a',
           'DR' => '0',
           'FM' => '1',
           'FD' => '1',
           };
           }
   my $options_ref = $self->{_options};
   if (defined($native_options_ref)) 
           {
     # Copy in new options.
     foreach (keys %$native_options_ref) 
           {
       $options_ref->{$_} = $native_options_ref->{$_};
           } 
           } 
   # Process the options.
   my($options) = '';
   foreach (sort keys %$options_ref) 
           {
     next if (generic_option($_));
     $options .= $_ . '=' . $options_ref->{$_} . '&';
           }
     chop $options;
  $self->{_next_url} = $self->{_options}{'search_url'} .'?'. $self->hash_to_cgi_string($self->{_options});
           } 

# private
sub native_retrieve_some {
    my ($self) = @_;
    print STDERR "**Snap::native_retrieve_some()\n" if $self->{_debug};
    
    # Fast exit if already done:
    return undef if (!defined($self->{_next_url}));
    
    # If this is not the first page of results, sleep so as to not
    # overload the server:
    $self->user_agent_delay if 1 < $self->{'_next_to_retrieve'};
    
    # Get some:
    print STDERR "**Requesting (",$self->{_next_url},")\n" if $self->{_debug};
    my($response) = $self->http_request('GET', $self->{_next_url});
    $self->{response} = $response;
    if (!$response->is_success) 
      {
      return undef;
      }
    $self->{'_next_url'} = undef;
    print STDERR "**Found Some\n" if $self->{_debug};
    # parse the output
    my ($HEADER, $HITS, $DESC) = qw(HE HI DE);
    my $state = $HEADER;
    my $hit = ();
    my $hits_found = 0;
    foreach ($self->split_lines($response->content()))
          {
     next if m@^$@; # short circuit for blank lines
     print STDERR " * $state ===$_=== " if 2 <= $self->{'_debug'};
     if (m@^<br><blockquote><font.*?>@i) {
       print STDERR "**Beginning Line...\n" if ($self->{_debug});
       $state = $HITS;

   } if ($state eq $HITS && m@^<font><a href="/slog/.*?&u=([^"]+)">(.*)</a>.*?<br>(.*)<br>@i) {
       print STDERR "**Found a URL\n" if 2 <= $self->{_debug};
       my ($url,$title, $desc) = ($1,$2,$3);
       if (defined($hit)) 
         {
        push(@{$self->{cache}}, $hit);
         };
       $hit = new WWW::SearchResult;
       $hit->add_url(uri_unescape($url));
       $hits_found++;
       $hit->title(strip_tags($title));
       $hit->description(strip_tags($desc));
       $state = $HITS;

   } elsif ($state eq $HITS && m|<font><b><a href="http://redirect.*?u=([^"]+)\&q=.*?>(.*)</a></b>.*?<br>(.*)<br>|i) {
       print STDERR "**Found a URL\n" if 2 <= $self->{_debug};
       my ($url,$title, $desc) = ($1,$2,$3);
       if (defined($hit)) 
         {
        push(@{$self->{cache}}, $hit);
         };
       $hit = new WWW::SearchResult;
       $hit->add_url(uri_unescape($url));
       $hits_found++;
       $hit->title(strip_tags($title));
       $hit->description(strip_tags($desc));
       $state = $HITS;

   } elsif ($state eq $HITS && m|<A HREF="([^"]+)">Next</A>|i) {
       print STDERR "**Found 'next' Tag\n" if 2 <= $self->{_debug};
       my $sURL = $1;
       $self->{'_next_url'} = $self->{'search_base_url'} . $sURL;
       print STDERR " **Next Tag is: ", $self->{'_next_url'}, "\n" if 2 <= $self->{_debug};
       $state = $HITS;
       } 
     else 
       {
       print STDERR "**Nothing Matched\n" if 2 <= $self->{_debug};
       }
       } 
    if (defined($hit)) {
    push(@{$self->{cache}}, $hit);
       } 
    return $hits_found;
       } # native_retrieve_some
1;


