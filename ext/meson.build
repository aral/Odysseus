shared_library('fts5', 'fts5.c', 'fts5.h', 'fts5-static.h', link_args: '-lm',
        dependencies: [dependency('sqlite3')],
        c_args: ['-DSQLITE_CORE'],
        install: false)
