package Pakket::Role::HasLibDir;

# ABSTRACT: a Role to add lib directory functionality

use Moose::Role;

use Carp qw< croak >;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use File::Copy::Recursive qw< dircopy >;
use Time::HiRes qw< time >;
use Log::Any qw< $log >;
use English qw< -no_match_vars >;

has 'pakket_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'libraries_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_libraries_dir',
);

has 'active_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_active_dir',
);

has 'work_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_work_dir',
);

sub _build_libraries_dir {
    my $self = shift;

    my $libraries_dir = $self->pakket_dir->child('libraries');

    $libraries_dir->is_dir
        or $libraries_dir->mkpath();

    return $libraries_dir;
}

sub _build_active_dir {
    my $self = shift;

    return $self->libraries_dir->child('active');
}

sub _build_work_dir {
    my $self = shift;

    my $work_dir = $self->libraries_dir->child( time() );

    $work_dir->exists
        and croak( $log->critical(
            "Internal installation directory exists ($work_dir), exiting",
        ) );

    $work_dir->mkpath();

    # we copy any previous installation
    if ( $self->active_dir->exists ) {
        my $orig_work_dir = eval { my $link = readlink $self->active_dir } or do {
            croak( $log->critical("$self->active_dir is not a symlink") );
        };

        dircopy( $self->libraries_dir->child($orig_work_dir), $work_dir );
    }
    $log->debugf( 'Created new working directory %s', $work_dir );

    return $work_dir;
}

sub activate_work_dir {
    my $self     = shift;
    my $work_dir = $self->work_dir;

    # The only way to make a symlink point somewhere else in an atomic way is
    # to create a new symlink pointing to the target, and then rename it to the
    # existing symlink (that is, overwriting it).
    #
    # This actually works, but there is a caveat: how to generate a name for
    # the new symlink? File::Temp will both create a new file name and open it,
    # returning a handle; not what we need.
    #
    # So, we just create a file name that looks like 'active_P_T.tmp', where P
    # is the pid and T is the current time.
    my $active_temp
        = $self->libraries_dir->child(
        sprintf( 'active_%s_%s.tmp', $PID, time() ),
        );

    if ( $active_temp->exists ) {

        # Huh? why does this temporary pathname exist? Try to delete it...
        $log->debug('Deleting existing temporary active object');

        $active_temp->remove
            or croak( $log->error(
                'Could not activate new installation (temporary symlink remove failed)'
            ) );
    }

    $log->debugf( 'Setting temporary active symlink to new work directory %s',
        $work_dir );

    symlink( $work_dir->basename, $active_temp )
        or croak( $log->error(
            'Could not activate new installation (temporary symlink create failed)'
        ) );

    $active_temp->move($self->active_dir)
        or croak( $log->error(
            'Could not atomically activate new installation (symlink rename failed)'
        ) );
}

sub remove_old_libraries {
    my $self = shift;

    my $keep = 1;

    my @dirs = sort { $a->stat->mtime <=> $b->stat->mtime }
        grep +( $_->basename ne 'active' && $_->is_dir ),
        $self->libraries_dir->children;

    my $num_dirs = @dirs;
    foreach my $dir (@dirs) {
        $num_dirs-- <= $keep and last;
        $log->debug("Removing old directory: $dir");
        path($dir)->remove_tree( { 'safe' => 0 } );
    }
}

no Moose::Role;
1;
__END__