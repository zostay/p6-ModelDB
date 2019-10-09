use v6;

unit package ModelDB;

use DBIish;

class Connector {
    has UInt $.max-connections = 16;
    has UInt $.tries = 2;

    has Capture $.connect-args;

    has @!available;
    has %!in-use;

    # Mutix to protect @!available
    has Lock $!mutex .= new;

    method !connect() {
        DBIish.connect(|$!connect-args);
    }

    method acquire() {
        my $dbh;
        $!mutex.protect: {
            $dbh = self!connect;
            %!in-use{ $dbh.WHICH } = $dbh;
        }
        $dbh;
    }

    method release($dbh) {
        $!mutex.protect: {
            push @!available, %!in-use{ $dbh.WHICH }:delete;
        }
    }

    method try-with($dbh, &code) {
        my $result;

        try {
            for ^$!tries {
                $result := code($dbh);
                last;

                CATCH {
                    when X::DBDish::DBError {
                        %!in-use{ $dbh.WHICH }:delete;
                        $dbh = self!connect;
                        %!in-use{ $dbh.WHICH } = $dbh;
                    }
                }
            }
        }

        $result;
    }

    method run(&code) {
        my $dbh = self.acquire;

        LEAVE self.release($dbh);

        self.try-with($dbh, &code);
    }

    method last-insert-rowid($dbh) {
        my $sth = do given $dbh {
            use DBDish::SQLite::Connection;
            use DBDish::mysql::Connection;

            when DBDish::SQLite::Connection {
                $dbh.prepare('SELECT last_insert_rowid()');
            }
            when DBDish::mysql::Connection {
                $dbh.prepare('SELECT last_insert_id()');
            }
            default {
                die "Unsupported database error";
            }
        }

        $sth.execute;
        $sth.fetchrow[0];
    }
}

=begin pod

=head1 NAME

ModelDB::Connector - manages the connections to the database

=head1 DESCRIPTION

This provides tooling used inside of ModelDB for managing database connections, recovering from lost connections, etc. This is still pretty immature so I don't really want to expose and document the innards yet.

=end pod
