# $Header: /raid/cvsroot/rt/lib/RT/Condition/QueueChange.pm,v 1.2 2001/11/06 23:04:18 jesse Exp $
# Copyright 1996-2001 Jesse Vincent <jesse@fsck.com> 
# Released under the terms of the GNU General Public License

package RT::Condition::QueueChange;
require RT::Condition::Generic;

@ISA = qw(RT::Condition::Generic);


=head2 IsApplicable

If the queue has changed.

=cut

sub IsApplicable {
    my $self = shift;
    if ($self->TransactionObj->Field eq 'Queue') {
	    return(1);
    } 
    else {
	    return(undef);
    }
}

1;

