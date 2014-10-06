# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2014 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

package RT::Interface::Email::Authz::Default;

use strict;
use warnings;

use Role::Basic 'with';
with 'RT::Interface::Email::Role';

=head1 NAME

RT::Interface::Email::Authz::Default - RT's core authorization for the mail gateway

=head1 SYNOPSIS

This module B<should not> be explicitly included in
L<RT_Config/@MailPlugins>; RT includes it automatically.  It provides
authorization checks for the core the C<comment> and C<correspond>
actions, via examining RT's standard rights for C<CommentOnTicket>,
C<ReplyToTicket>, or C<CreateTicket> as necessary.

=cut

sub CheckACL {
    my %args = (
        Message     => undef,
        CurrentUser => undef,
        Ticket      => undef,
        Queue       => undef,
        Action      => undef,
        @_,
    );

    my @emails;
    for my $CurrentUser ( ref $args{CurrentUser} eq 'ARRAY' ? @{ $args{CurrentUser} } : $args{CurrentUser} ) {
        my $principal = $CurrentUser->PrincipalObj;
        push @emails, $CurrentUser->UserObj->EmailAddress;

        if ( $args{'Ticket'} && $args{'Ticket'}->Id ) {
            if ( $args{'Action'} =~ /^comment$/i ) {
                return $CurrentUser if $principal->HasRight( Object => $args{'Ticket'}, Right => 'CommentOnTicket' );
            }
            elsif ( $args{'Action'} =~ /^correspond$/i ) {
                return $CurrentUser if $principal->HasRight( Object => $args{'Ticket'}, Right => 'ReplyToTicket' );
            }
            else {
                $RT::Logger->warning("Action '". ($args{'Action'}||'') ."' is unknown");
                return;
            }
        }

        # We're creating a ticket
        elsif ( $args{'Action'} =~ /^(comment|correspond)$/i ) {
            return $CurrentUser if $principal->HasRight( Object => $args{'Queue'}, Right => 'CreateTicket' );
        }
        else {
            $RT::Logger->warning( "Action '" . ( $args{'Action'} || '' ) . "' is unknown with no ticket" );
            return;
        }
    }

    my $msg;
    my $email = join ", ", @emails;
    my $qname = $args{'Queue'}->Name;
    if ( $args{'Ticket'} && $args{'Ticket'}->Id ) {
        my $tid = $args{'Ticket'}->id;

        if ( $args{'Action'} =~ /^comment$/i ) {
            $msg = (@emails ? "$email has" : "$email have") . " no right to comment on ticket $tid in queue $qname";
        }
        elsif ( $args{'Action'} =~ /^correspond$/i ) {
            $msg = (@emails ? "$email has" : "$email have") . " no right to reply to ticket $tid in queue $qname";

            # Also notify the owner
            MailError(
                To          => RT->Config->Get('OwnerEmail'),
                Subject     => "Failed attempt to reply to a ticket by email, from $email",
                Explanation => <<EOT,
$email attempted to reply to a ticket via email in the queue $qname; you
might need to grant 'Everyone' the ReplyToTicket right.
EOT
            );
        }
    }
    # We're creating a ticket
    elsif ( $args{'Action'} =~ /^(comment|correspond)$/i ) {
        $msg = (@emails ? "$email has" : "$email have") . " no right to create tickets in queue $qname";

        # Also notify the owner
        MailError(
            To          => RT->Config->Get('OwnerEmail'),
            Subject     => "Failed attempt to create a ticket by email, from $email",
            Explanation => <<EOT,
$email attempted to create a ticket via email in the queue $qname; you
might need to grant 'Everyone' the CreateTicket right.
EOT
        );
    }

    MailError(
        Subject     => "Permission Denied",
        Explanation => $msg,
        FAILURE     => 1,
    );
}

1;