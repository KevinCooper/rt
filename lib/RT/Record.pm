# {{{ BEGIN BPS TAGGED BLOCK
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2004 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
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
# }}} END BPS TAGGED BLOCK
=head1 NAME

  RT::Record - Base class for RT record objects

=head1 SYNOPSIS


=head1 DESCRIPTION


=begin testing

ok (require RT::Record);

=end testing

=head1 METHODS

=cut

package RT::Record;
use RT::Date;
use RT::User;
use RT::Attributes;
use RT::Base;
use DBIx::SearchBuilder::Record::Cachable;

use strict;
use vars qw/@ISA $_TABLE_ATTR/;

@ISA = qw(RT::Base);

if ($RT::DontCacheSearchBuilderRecords ) {
    push (@ISA, 'DBIx::SearchBuilder::Record');
} else {
    push (@ISA, 'DBIx::SearchBuilder::Record::Cachable');

}

# {{{ sub _Init 

sub _Init {
    my $self = shift;
    $self->_BuildTableAttributes unless ($_TABLE_ATTR->{ref($self)});
    $self->CurrentUser(@_);
}

# }}}

# {{{ _PrimaryKeys

=head2 _PrimaryKeys

The primary keys for RT classes is 'id'

=cut

sub _PrimaryKeys {
    my $self = shift;
    return ( ['id'] );
}

# }}}

=head2 Attributes

Return this object's attributes as an RT::Attributes object

=cut

sub Attributes {
    my $self = shift;
    
    unless ($self->{'attributes'}) {
        $self->{'attributes'} = RT::Attributes->new($self->CurrentUser);     
       $self->{'attributes'}->LimitToObject($self); 
    }
    return ($self->{'attributes'}); 

}


=head2 AddAttribute { Name, Description, Content }

Adds a new attribute for this object.

=cut

sub AddAttribute {
    my $self = shift;
    my %args = ( Name        => undef,
                 Description => undef,
                 Content     => undef,
                 @_ );

    my $attr = RT::Attribute->new( $self->CurrentUser );
    my ( $id, $msg ) = $attr->Create( 
                                      Object    => $self,
                                      Name        => $args{'Name'},
                                      Description => $args{'Description'},
                                      Content     => $args{'Content'} );

    $self->Attributes->RedoSearch;
    
    return ($id, $msg);
}


=head2 SetAttribute { Name, Description, Content }

Like AddAttribute, but replaces all existing attributes with the same Name.

=cut

sub SetAttribute {
    my $self = shift;
    my %args = ( Name        => undef,
                 Description => undef,
                 Content     => undef,
                 @_ );

    my @AttributeObjs = $self->Attributes->Named( $args{'Name'} )
        or return $self->AddAttribute( %args );

    my $AttributeObj = pop( @AttributeObjs );
    $_->Delete foreach @AttributeObjs;

    $AttributeObj->SetDescription( $args{'Description'} );
    $AttributeObj->SetContent( $args{'Content'} );

    $self->Attributes->RedoSearch;
    return 1;
}

=head2 DeleteAttribute NAME

Deletes all attributes with the matching name for this object.

=cut

sub DeleteAttribute {
    my $self = shift;
    my $name = shift;
    return $self->Attributes->DeleteEntry( Name => $name );
}

=head2 FirstAttribute NAME

Returns the value of the first attribute with the matching name
for this object, or C<undef> if no such attributes exist.

=cut

sub FirstAttribute {
    my $self = shift;
    my $name = shift;
    return ($self->Attributes->Named( $name ))[0];
}


# {{{ sub _Handle 
sub _Handle {
    my $self = shift;
    return ($RT::Handle);
}

# }}}

# {{{ sub Create 

=item  Create PARAMHASH

Takes a PARAMHASH of Column -> Value pairs.
If any Column has a Validate$PARAMNAME subroutine defined and the 
value provided doesn't pass validation, this routine returns
an error.

If this object's table has any of the following atetributes defined as
'Auto', this routine will automatically fill in their values.

=cut

sub Create {
    my $self    = shift;
    my %attribs = (@_);
    foreach my $key ( keys %attribs ) {
        my $method = "Validate$key";
        unless ( $self->$method( $attribs{$key} ) ) {
            if (wantarray) {
                return ( 0, $self->loc('Invalid value for [_1]', $key) );
            }
            else {
                return (0);
            }
        }
    }
    my $now = RT::Date->new( $self->CurrentUser );
    $now->Set( Format => 'unix', Value => time );
    $attribs{'Created'} = $now->ISO() if ( $self->_Accessible( 'Created', 'auto' ) && !$attribs{'Created'});

    if ($self->_Accessible( 'Creator', 'auto' ) && !$attribs{'Creator'}) {
         $attribs{'Creator'} = $self->CurrentUser->id || '0'; 
    }
    $attribs{'LastUpdated'} = $now->ISO()
      if ( $self->_Accessible( 'LastUpdated', 'auto' ) && !$attribs{'LastUpdated'});

    $attribs{'LastUpdatedBy'} = $self->CurrentUser->id || '0'
      if ( $self->_Accessible( 'LastUpdatedBy', 'auto' ) && !$attribs{'LastUpdatedBy'});

    my $id = $self->SUPER::Create(%attribs);
    if ( UNIVERSAL::isa( $id, 'Class::ReturnValue' ) ) {
        if ( $id->errno ) {
            if (wantarray) {
                return ( 0,
                    $self->loc( "Internal Error: [_1]", $id->{error_message} ) );
            }
            else {
                return (0);
            }
        }
    }
    # If the object was created in the database, 
    # load it up now, so we're sure we get what the database 
    # has.  Arguably, this should not be necessary, but there
    # isn't much we can do about it.

   unless ($id) { 
    if (wantarray) {
        return ( $id, $self->loc('Object could not be created') );
    }
    else {
        return ($id);
    }

   }

    if  (UNIVERSAL::isa('errno',$id)) {
        exit(0);
       warn "It's here!";
        return(undef);
    }

    $self->Load($id) if ($id);



    if (wantarray) {
        return ( $id, $self->loc('Object created') );
    }
    else {
        return ($id);
    }

}

# }}}

# {{{ sub LoadByCols

=head2 LoadByCols

Override DBIx::SearchBuilder::LoadByCols to do case-insensitive loads if the 
DB is case sensitive

=cut

sub LoadByCols {
    my $self = shift;
    my %hash = (@_);

    # We don't want to hang onto this
    delete $self->{'attributes'};

    # If this database is case sensitive we need to uncase objects for
    # explicit loading
    if ( $self->_Handle->CaseSensitive ) {
        my %newhash;
        foreach my $key ( keys %hash ) {

            # If we've been passed an empty value, we can't do the lookup. 
            # We don't need to explicitly downcase integers or an id.
            if ( $key =~ '^id$'
                || !defined( $hash{$key} )
                || $hash{$key} =~ /^\d+$/
                 )
            {
                $newhash{$key} = $hash{$key};
            }
            else {
                my ($op, $val);
                ($key, $op, $val) = $self->_Handle->_MakeClauseCaseInsensitive($key, '=', $hash{$key});
                $newhash{$key}->{operator} = $op;
                $newhash{$key}->{value} = $val;
            }
        }

        # We've clobbered everything we care about. bash the old hash
        # and replace it with the new hash
        %hash = %newhash;
    }
    $self->SUPER::LoadByCols(%hash);
}

# }}}

# {{{ Datehandling

# There is room for optimizations in most of those subs:

# {{{ LastUpdatedObj

sub LastUpdatedObj {
    my $self = shift;
    my $obj  = new RT::Date( $self->CurrentUser );

    $obj->Set( Format => 'sql', Value => $self->LastUpdated );
    return $obj;
}

# }}}

# {{{ CreatedObj

sub CreatedObj {
    my $self = shift;
    my $obj  = new RT::Date( $self->CurrentUser );

    $obj->Set( Format => 'sql', Value => $self->Created );

    return $obj;
}

# }}}

# {{{ AgeAsString
#
# TODO: This should be deprecated
#
sub AgeAsString {
    my $self = shift;
    return ( $self->CreatedObj->AgeAsString() );
}

# }}}

# {{{ LastUpdatedAsString

# TODO this should be deprecated

sub LastUpdatedAsString {
    my $self = shift;
    if ( $self->LastUpdated ) {
        return ( $self->LastUpdatedObj->AsString() );

    }
    else {
        return "never";
    }
}

# }}}

# {{{ CreatedAsString
#
# TODO This should be deprecated 
#
sub CreatedAsString {
    my $self = shift;
    return ( $self->CreatedObj->AsString() );
}

# }}}

# {{{ LongSinceUpdateAsString
#
# TODO This should be deprecated
#
sub LongSinceUpdateAsString {
    my $self = shift;
    if ( $self->LastUpdated ) {

        return ( $self->LastUpdatedObj->AgeAsString() );

    }
    else {
        return "never";
    }
}

# }}}

# }}} Datehandling

# {{{ sub _Set 
sub _Set {
    my $self = shift;

    my %args = (
        Field => undef,
        Value => undef,
        IsSQL => undef,
        @_
    );

    #if the user is trying to modify the record
    # TODO: document _why_ this code is here

    if ( ( !defined( $args{'Field'} ) ) || ( !defined( $args{'Value'} ) ) ) {
        $args{'Value'} = 0;
    }

    $self->_SetLastUpdated();
    my ( $val, $msg ) = $self->SUPER::_Set(
        Field => $args{'Field'},
        Value => $args{'Value'},
        IsSQL => $args{'IsSQL'}
    );
}

# }}}

# {{{ sub _SetLastUpdated

=head2 _SetLastUpdated

This routine updates the LastUpdated and LastUpdatedBy columns of the row in question
It takes no options. Arguably, this is a bug

=cut

sub _SetLastUpdated {
    my $self = shift;
    use RT::Date;
    my $now = new RT::Date( $self->CurrentUser );
    $now->SetToNow();

    if ( $self->_Accessible( 'LastUpdated', 'auto' ) ) {
        my ( $msg, $val ) = $self->__Set(
            Field => 'LastUpdated',
            Value => $now->ISO
        );
    }
    if ( $self->_Accessible( 'LastUpdatedBy', 'auto' ) ) {
        my ( $msg, $val ) = $self->__Set(
            Field => 'LastUpdatedBy',
            Value => $self->CurrentUser->id
        );
    }
}

# }}}

# {{{ sub CreatorObj 

=head2 CreatorObj

Returns an RT::User object with the RT account of the creator of this row

=cut

sub CreatorObj {
    my $self = shift;
    unless ( exists $self->{'CreatorObj'} ) {

        $self->{'CreatorObj'} = RT::User->new( $self->CurrentUser );
        $self->{'CreatorObj'}->Load( $self->Creator );
    }
    return ( $self->{'CreatorObj'} );
}

# }}}

# {{{ sub LastUpdatedByObj

=head2 LastUpdatedByObj

  Returns an RT::User object of the last user to touch this object

=cut

sub LastUpdatedByObj {
    my $self = shift;
    unless ( exists $self->{LastUpdatedByObj} ) {
        $self->{'LastUpdatedByObj'} = RT::User->new( $self->CurrentUser );
        $self->{'LastUpdatedByObj'}->Load( $self->LastUpdatedBy );
    }
    return $self->{'LastUpdatedByObj'};
}

# }}}

# {{{ sub URI 

=head2 URI

Returns this record's URI

=cut

sub URI {
    my $self = shift;
    my $uri = RT::URI::fsck_com_rt->new($self->CurrentUser);
    return($uri->URIForObject($self));
}

# }}}
 




=head2 SQLType attribute

return the SQL type for the attribute 'attribute' as stored in _ClassAccessible

=cut

sub SQLType {
    my $self = shift;
    my $field = shift;

    return ($self->_Accessible($field, 'type'));


}

require Encode::compat if $] < 5.007001;
require Encode;




sub __Value {
    my $self  = shift;
    my $field = shift;
    my %args = ( decode_utf8 => 1,
                 @_ );

    unless (defined $field && $field) {
        $RT::Logger->error("$self __Value called with undef field");
    }
    my $value = $self->SUPER::__Value($field);

    return('') if ( !defined($value) || $value eq '');

    return Encode::decode_utf8($value) || $value if $args{'decode_utf8'};
    return $value;
}

# Set up defaults for DBIx::SearchBuilder::Record::Cachable

sub _CacheConfig {
  {
     'cache_p'        => 1,
     'cache_for_sec'  => 30,
  }
}



sub _BuildTableAttributes {
    my $self = shift;

    my $attributes;
    if ( UNIVERSAL::can( $self, '_CoreAccessible' ) ) {
       $attributes = $self->_CoreAccessible();
    } elsif ( UNIVERSAL::can( $self, '_ClassAccessible' ) ) {
       $attributes = $self->_ClassAccessible();

    }

    foreach my $column (%$attributes) {
        foreach my $attr ( %{ $attributes->{$column} } ) {
            $_TABLE_ATTR->{ref($self)}->{$column}->{$attr} = $attributes->{$column}->{$attr};
        }
    }
    if ( UNIVERSAL::can( $self, '_OverlayAccessible' ) ) {
        $attributes = $self->_OverlayAccessible();

        foreach my $column (%$attributes) {
            foreach my $attr ( %{ $attributes->{$column} } ) {
                $_TABLE_ATTR->{ref($self)}->{$column}->{$attr} = $attributes->{$column}->{$attr};
            }
        }
    }
    if ( UNIVERSAL::can( $self, '_VendorAccessible' ) ) {
        $attributes = $self->_VendorAccessible();

        foreach my $column (%$attributes) {
            foreach my $attr ( %{ $attributes->{$column} } ) {
                $_TABLE_ATTR->{ref($self)}->{$column}->{$attr} = $attributes->{$column}->{$attr};
            }
        }
    }
    if ( UNIVERSAL::can( $self, '_LocalAccessible' ) ) {
        $attributes = $self->_LocalAccessible();

        foreach my $column (%$attributes) {
            foreach my $attr ( %{ $attributes->{$column} } ) {
                $_TABLE_ATTR->{ref($self)}->{$column}->{$attr} = $attributes->{$column}->{$attr};
            }
        }
    }

}


=head2 _ClassAccessible 

Overrides the "core" _ClassAccessible using $_TABLE_ATTR. Behaves identical to the version in
DBIx::SearchBuilder::Record

=cut

sub _ClassAccessible {
    my $self = shift;
    return $_TABLE_ATTR->{ref($self)};
}

=head2 _Accessible COLUMN ATTRIBUTE

returns the value of ATTRIBUTE for COLUMN


=cut 

sub _Accessible  {
  my $self = shift;
  my $column = shift;
  my $attribute = lc(shift);
  return 0 unless defined ($_TABLE_ATTR->{ref($self)}->{$column});
  return $_TABLE_ATTR->{ref($self)}->{$column}->{$attribute} || 0;

}

=head2 _EncodeLOB BODY MIME_TYPE

Takes a potentially large attachment. Returns (ContentEncoding, EncodedBody) based on system configuration and selected database

=cut

sub _EncodeLOB {
        my $self = shift;
        my $Body = shift;
        my $MIMEType = shift;

        my $ContentEncoding = 'none';

        #get the max attachment length from RT
        my $MaxSize = $RT::MaxAttachmentSize;

        #if the current attachment contains nulls and the
        #database doesn't support embedded nulls

        if ( $RT::AlwaysUseBase64 or
             ( !$RT::Handle->BinarySafeBLOBs ) && ( $Body =~ /\x00/ ) ) {

            # set a flag telling us to mimencode the attachment
            $ContentEncoding = 'base64';

            #cut the max attchment size by 25% (for mime-encoding overhead.
            $RT::Logger->debug("Max size is $MaxSize\n");
            $MaxSize = $MaxSize * 3 / 4;
        # Some databases (postgres) can't handle non-utf8 data
        } elsif (    !$RT::Handle->BinarySafeBLOBs
                  && $MIMEType !~ /text\/plain/gi
                  && !Encode::is_utf8( $Body, 1 ) ) {
              $ContentEncoding = 'quoted-printable';
        }

        #if the attachment is larger than the maximum size
        if ( ($MaxSize) and ( $MaxSize < length($Body) ) ) {

            # if we're supposed to truncate large attachments
            if ($RT::TruncateLongAttachments) {

                # truncate the attachment to that length.
                $Body = substr( $Body, 0, $MaxSize );

            }

            # elsif we're supposed to drop large attachments on the floor,
            elsif ($RT::DropLongAttachments) {

                # drop the attachment on the floor
                $RT::Logger->info( "$self: Dropped an attachment of size " . length($Body) . "\n" . "It started: " . substr( $Body, 0, 60 ) . "\n" );
                return ("none", "Large attachment dropped" );
            }
        }

        # if we need to mimencode the attachment
        if ( $ContentEncoding eq 'base64' ) {

            # base64 encode the attachment
            Encode::_utf8_off($Body);
            $Body = MIME::Base64::encode_base64($Body);

        } elsif ($ContentEncoding eq 'quoted-printable') {
            Encode::_utf8_off($Body);
            $Body = MIME::QuotedPrint::encode($Body);
        }


        return ($ContentEncoding, $Body);

}


# {{{ LINKDIRMAP
# A helper table for links mapping to make it easier
# to build and parse links between tickets

use vars '%LINKDIRMAP';

%LINKDIRMAP = (
    MemberOf => { Base => 'MemberOf',
                  Target => 'HasMember', },
    RefersTo => { Base => 'RefersTo',
                Target => 'ReferredToBy', },
    DependsOn => { Base => 'DependsOn',
                   Target => 'DependedOnBy', },
    MergedInto => { Base => 'MergedInto',
                   Target => 'MergedInto', },

);

sub Update {
    my $self = shift;

    my %args = (
        ARGSRef         => undef,
        AttributesRef   => undef,
        AttributePrefix => undef,
        @_
    );

    my $attributes = $args{'AttributesRef'};
    my $ARGSRef    = $args{'ARGSRef'};
    my @results;

    foreach my $attribute (@$attributes) {
        my $value;
        if ( defined $ARGSRef->{$attribute} ) {
            $value = $ARGSRef->{$attribute};
        }
        elsif (
            defined( $args{'AttributePrefix'} )
            && defined(
                $ARGSRef->{ $args{'AttributePrefix'} . "-" . $attribute }
            )
          )
        {
            $value = $ARGSRef->{ $args{'AttributePrefix'} . "-" . $attribute };

        }
        else {
            next;
        }

        $value =~ s/\r\n/\n/gs;


        # If Queue is 'General', we want to resolve the queue name for
        # the object.

        # This is in an eval block because $object might not exist.
        # and might not have a Name method. But "can" won't find autoloaded
        # items. If it fails, we don't care
        eval {
            my $object = $attribute . "Obj";
            next if ($self->$object->Name eq $value);
        };
        next if ( $value eq $self->$attribute() );
        my $method = "Set$attribute";
        my ( $code, $msg ) = $self->$method($value);

        my ($prefix) = ref($self) =~ /RT::(\w+)/;
        push @results,
          $self->loc( "$prefix [_1]", $self->id ) . ': '
          . $self->loc($attribute) . ': '
          . $self->CurrentUser->loc_fuzzy($msg);

=for loc
                                   "[_1] could not be set to [_2].",       # loc
                                   "That is already the current value",    # loc
                                   "No value sent to _Set!\n",             # loc
                                   "Illegal value for [_1]",               # loc
                                   "The new value has been set.",          # loc
                                   "No column specified",                  # loc
                                   "Immutable field",                      # loc
                                   "Nonexistant field?",                   # loc
                                   "Invalid data",                         # loc
                                   "Couldn't find row",                    # loc
                                   "Missing a primary key?: [_1]",         # loc
                                   "Found Object",                         # loc
=cut

    }

    return @results;
}

# {{{ Routines dealing with Links between tickets

# {{{ Link Collections

# {{{ sub Members

=head2 Members

  This returns an RT::Links object which references all the tickets 
which are 'MembersOf' this ticket

=cut

sub Members {
    my $self = shift;
    return ( $self->_Links( 'Target', 'MemberOf' ) );
}

# }}}

# {{{ sub MemberOf

=head2 MemberOf

  This returns an RT::Links object which references all the tickets that this
ticket is a 'MemberOf'

=cut

sub MemberOf {
    my $self = shift;
    return ( $self->_Links( 'Base', 'MemberOf' ) );
}

# }}}

# {{{ RefersTo

=head2 RefersTo

  This returns an RT::Links object which shows all references for which this ticket is a base

=cut

sub RefersTo {
    my $self = shift;
    return ( $self->_Links( 'Base', 'RefersTo' ) );
}

# }}}

# {{{ ReferredToBy

=head2 ReferredToBy

  This returns an RT::Links object which shows all references for which this ticket is a target

=cut

sub ReferredToBy {
    my $self = shift;
    return ( $self->_Links( 'Target', 'RefersTo' ) );
}

# }}}

# {{{ DependedOnBy

=head2 DependedOnBy

  This returns an RT::Links object which references all the tickets that depend on this one

=cut

sub DependedOnBy {
    my $self = shift;
    return ( $self->_Links( 'Target', 'DependsOn' ) );
}

# }}}



=head2 HasUnresolvedDependencies

  Takes a paramhash of Type (default to '__any').  Returns true if
$self->UnresolvedDependencies returns an object with one or more members
of that type.  Returns false otherwise


=begin testing

my $t1 = RT::Ticket->new($RT::SystemUser);
my ($id, $trans, $msg) = $t1->Create(Subject => 'DepTest1', Queue => 'general');
ok($id, "Created dep test 1 - $msg");

my $t2 = RT::Ticket->new($RT::SystemUser);
my ($id2, $trans, $msg2) = $t2->Create(Subject => 'DepTest2', Queue => 'general');
ok($id2, "Created dep test 2 - $msg2");
my $t3 = RT::Ticket->new($RT::SystemUser);
my ($id3, $trans, $msg3) = $t3->Create(Subject => 'DepTest3', Queue => 'general', Type => 'approval');
ok($id3, "Created dep test 3 - $msg3");
my ($addid, $addmsg);
ok (($addid, $addmsg) =$t1->AddLink( Type => 'DependsOn', Target => $t2->id));
ok ($addid, $addmsg);
ok (($addid, $addmsg) =$t1->AddLink( Type => 'DependsOn', Target => $t3->id));

ok ($addid, $addmsg);
ok ($t1->HasUnresolvedDependencies, "Ticket ".$t1->Id." has unresolved deps");
ok (!$t1->HasUnresolvedDependencies( Type => 'blah' ), "Ticket ".$t1->Id." has no unresolved blahs");
ok ($t1->HasUnresolvedDependencies( Type => 'approval' ), "Ticket ".$t1->Id." has unresolved approvals");
ok (!$t2->HasUnresolvedDependencies, "Ticket ".$t2->Id." has no unresolved deps");
;

my ($rid, $rmsg)= $t1->Resolve();
ok(!$rid, $rmsg);
ok($t2->Resolve);
($rid, $rmsg)= $t1->Resolve();
ok(!$rid, $rmsg);
ok($t3->Resolve);
($rid, $rmsg)= $t1->Resolve();
ok($rid, $rmsg);


=end testing

=cut

sub HasUnresolvedDependencies {
    my $self = shift;
    my %args = (
        Type   => undef,
        @_
    );

    my $deps = $self->UnresolvedDependencies;

    if ($args{Type}) {
        $deps->Limit( FIELD => 'Type', 
              OPERATOR => '=',
              VALUE => $args{Type}); 
    }
    else {
	    $deps->IgnoreType;
    }

    if ($deps->Count > 0) {
        return 1;
    }
    else {
        return (undef);
    }
}


# {{{ UnresolvedDependencies 

=head2 UnresolvedDependencies

Returns an RT::Tickets object of tickets which this ticket depends on
and which have a status of new, open or stalled. (That list comes from
RT::Queue->ActiveStatusArray

=cut


sub UnresolvedDependencies {
    my $self = shift;
    my $deps = RT::Tickets->new($self->CurrentUser);

    my @live_statuses = RT::Queue->ActiveStatusArray();
    foreach my $status (@live_statuses) {
        $deps->LimitStatus(VALUE => $status);
    }
    $deps->LimitDependedOnBy($self->Id);

    return($deps);

}

# }}}

# {{{ AllDependedOnBy

=head2 AllDependedOnBy

Returns an array of RT::Ticket objects which (directly or indirectly)
depends on this ticket; takes an optional 'Type' argument in the param
hash, which will limit returned tickets to that type, as well as cause
tickets with that type to serve as 'leaf' nodes that stops the recursive
dependency search.

=cut

sub AllDependedOnBy {
    my $self = shift;
    my $dep = $self->DependedOnBy;
    my %args = (
        Type   => undef,
	_found => {},
	_top   => 1,
        @_
    );

    while (my $link = $dep->Next()) {
	next unless ($link->BaseURI->IsLocal());
	next if $args{_found}{$link->BaseObj->Id};

	if (!$args{Type}) {
	    $args{_found}{$link->BaseObj->Id} = $link->BaseObj;
	    $link->BaseObj->AllDependedOnBy( %args, _top => 0 );
	}
	elsif ($link->BaseObj->Type eq $args{Type}) {
	    $args{_found}{$link->BaseObj->Id} = $link->BaseObj;
	}
	else {
	    $link->BaseObj->AllDependedOnBy( %args, _top => 0 );
	}
    }

    if ($args{_top}) {
	return map { $args{_found}{$_} } sort keys %{$args{_found}};
    }
    else {
	return 1;
    }
}

# }}}

# {{{ DependsOn

=head2 DependsOn

  This returns an RT::Links object which references all the tickets that this ticket depends on

=cut

sub DependsOn {
    my $self = shift;
    return ( $self->_Links( 'Base', 'DependsOn' ) );
}

# }}}




# {{{ sub _Links 

sub _Links {
    my $self = shift;

    #TODO: Field isn't the right thing here. but I ahave no idea what mnemonic ---
    #tobias meant by $f
    my $field = shift;
    my $type  = shift || "";

    unless ( $self->{"$field$type"} ) {
        $self->{"$field$type"} = new RT::Links( $self->CurrentUser );
            # at least to myself
            $self->{"$field$type"}->Limit( FIELD => $field,
                                           VALUE => $self->URI,
                                           ENTRYAGGREGATOR => 'OR' );
            $self->{"$field$type"}->Limit( FIELD => 'Type',
                                           VALUE => $type )
              if ($type);
    }
    return ( $self->{"$field$type"} );
}

# }}}

# }}}

# {{{ sub _AddLink

=head2 _AddLink

Takes a paramhash of Type and one of Base or Target. Adds that link to this ticket.


=cut


sub _AddLink {
    my $self = shift;
    my %args = ( Target => '',
                 Base   => '',
                 Type   => '',
                 Silent => undef,
                 @_ );


    # Remote_link is the URI of the object that is not this ticket
    my $remote_link;
    my $direction;

    if ( $args{'Base'} and $args{'Target'} ) {
        $RT::Logger->debug(
"$self tried to delete a link. both base and target were specified\n" );
        return ( 0, $self->loc("Can't specifiy both base and target") );
    }
    elsif ( $args{'Base'} ) {
        $args{'Target'} = $self->URI();
	my $class = ref($self);
        $remote_link    = $args{'Base'};
        $direction      = 'Target';
    }
    elsif ( $args{'Target'} ) {
        $args{'Base'} = $self->URI();
	my $class = ref($self);
        $remote_link  = $args{'Target'};
        $direction    = 'Base';
    }
    else {
        return ( 0, $self->loc('Either base or target must be specified') );
    }

    # {{{ Check if the link already exists - we don't want duplicates
    use RT::Link;
    my $old_link = RT::Link->new( $self->CurrentUser );
    $old_link->LoadByParams( Base   => $args{'Base'},
                             Type   => $args{'Type'},
                             Target => $args{'Target'} );
    if ( $old_link->Id ) {
        $RT::Logger->debug("$self Somebody tried to duplicate a link");
        return ( $old_link->id, $self->loc("Link already exists"), 0 );
    }

    # }}}


    # Storing the link in the DB.
    my $link = RT::Link->new( $self->CurrentUser );
    my ($linkid, $linkmsg) = $link->Create( Target => $args{Target},
                                  Base   => $args{Base},
                                  Type   => $args{Type} );

    unless ($linkid) {
        $RT::Logger->error("Link could not be created: ".$linkmsg);
        return ( 0, $self->loc("Link could not be created") );
    }

    my $TransString =
      "Record $args{'Base'} $args{Type} record $args{'Target'}.";

    return ( 1, $self->loc( "Link created ([_1])", $TransString ) );
}

# }}}

# {{{ sub _DeleteLink 

=head2 _DeleteLink

Delete a link. takes a paramhash of Base, Target and Type.
Either Base or Target must be null. The null value will 
be replaced with this ticket\'s id

=cut 

sub _DeleteLink {
    my $self = shift;
    my %args = (
        Base   => undef,
        Target => undef,
        Type   => undef,
        @_
    );

    #we want one of base and target. we don't care which
    #but we only want _one_

    my $direction;
    my $remote_link;

    if ( $args{'Base'} and $args{'Target'} ) {
        $RT::Logger->debug("$self ->_DeleteLink. got both Base and Target\n");
        return ( 0, $self->loc("Can't specifiy both base and target") );
    }
    elsif ( $args{'Base'} ) {
        $args{'Target'} = $self->URI();
	$remote_link = $args{'Base'};
    	$direction = 'Target';
    }
    elsif ( $args{'Target'} ) {
        $args{'Base'} = $self->URI();
	$remote_link = $args{'Target'};
        $direction='Base';
    }
    else {
        $RT::Logger->debug("$self: Base or Target must be specified\n");
        return ( 0, $self->loc('Either base or target must be specified') );
    }

    my $link = new RT::Link( $self->CurrentUser );
    $RT::Logger->debug( "Trying to load link: " . $args{'Base'} . " " . $args{'Type'} . " " . $args{'Target'} . "\n" );


    $link->LoadByParams( Base=> $args{'Base'}, Type=> $args{'Type'}, Target=>  $args{'Target'} );
    #it's a real link. 
    if ( $link->id ) {

        my $linkid = $link->id;
        $link->Delete();

        my $TransString = "Record $args{'Base'} no longer $args{Type} record $args{'Target'}.";
        return ( 1, $self->loc("Link deleted ([_1])", $TransString));
    }

    #if it's not a link we can find
    else {
        $RT::Logger->debug("Couldn't find that link\n");
        return ( 0, $self->loc("Link not found") );
    }
}

# }}}

eval "require RT::Record_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Record_Vendor.pm});
eval "require RT::Record_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Record_Local.pm});

1;
