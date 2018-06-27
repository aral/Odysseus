[CCode(cheader_filename = "fts5.h")]
namespace Sqlite_FTS5 {
    [CCode(cname = "sqlite3_fts5_init")]
    int init(Sqlite.Database db, out string errmsg, void *papi = null);
}
