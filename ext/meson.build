static_library('fts5', 'fts5.c', 'fts5.h', link_args: '-lm',
        install_dir: '/usr/share/Odysseus/',
        dependencies: [dependency('sqlite3')],
        c_args: ['-DSQLITE_CORE'],
        install: false)
