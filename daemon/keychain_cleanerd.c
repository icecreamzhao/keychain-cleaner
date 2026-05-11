#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <sqlite3.h>

typedef int (*system_fn)(const char *);

static int sys_exec(const char *cmd) {
    static system_fn s = NULL;
    if (!s) s = (system_fn)dlsym(RTLD_DEFAULT, "system");
    return s ? s(cmd) : -1;
}

#define KEYCHAIN_DB "/private/var/Keychains/keychain-2.db"
#define KEYCHAIN_WAL "/private/var/Keychains/keychain-2.db-wal"
#define KEYCHAIN_SHM "/private/var/Keychains/keychain-2.db-shm"
#define WORK_DIR "/var/jb/var/keychain_cleaner"
#define TRIGGER_FILE WORK_DIR "/trigger"
#define RESULT_FILE WORK_DIR "/result"
#define SECD_PLIST "/System/Library/LaunchDaemons/com.apple.securityd.plist"

static const char *tables[] = {"genp", "inet", "cert", "keys", NULL};

static int count_from_table(sqlite3 *db, const char *table, const char *pattern) {
    char sql[1024];
    snprintf(sql, sizeof(sql), "SELECT COUNT(*) FROM %s WHERE agrp LIKE \"%%%s%%\"", table, pattern);
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 0;
    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) count = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);
    return count;
}

static int delete_from_table(sqlite3 *db, const char *table, const char *pattern) {
    char sql[1024];
    snprintf(sql, sizeof(sql), "DELETE FROM %s WHERE agrp LIKE \"%%%s%%\"", table, pattern);
    char *err = NULL;
    if (sqlite3_exec(db, sql, NULL, NULL, &err) != SQLITE_OK) {
        fprintf(stderr, "DELETE %s: %s\n", table, err ? err : "unknown");
        sqlite3_free(err);
        return -1;
    }
    return sqlite3_changes(db);
}

int main(int argc, char **argv) {
    FILE *tf = fopen(TRIGGER_FILE, "r");
    if (!tf) { fprintf(stderr, "No trigger file\n"); return 1; }
    
    char bundle_id[256] = {0};
    if (!fgets(bundle_id, sizeof(bundle_id), tf)) { fclose(tf); return 1; }
    fclose(tf);
    
    size_t len = strlen(bundle_id);
    while (len > 0 && (bundle_id[len-1] == '\n' || bundle_id[len-1] == '\r'))
        bundle_id[--len] = '\0';
    if (len == 0) { fprintf(stderr, "Empty bundle ID\n"); return 1; }
    
    printf("Clearing keychain for: %s\n", bundle_id);
    
    printf("Stopping securityd...\n");
    sys_exec("launchctl unload " SECD_PLIST " 2>/dev/null");
    usleep(500000);
    
    int before = 0, total = 0, after = 0;
    
    chmod(KEYCHAIN_DB, 0644);
    
    sqlite3 *db;
    int rc = sqlite3_open_v2(KEYCHAIN_DB, &db, SQLITE_OPEN_READWRITE, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open DB: %s\n", sqlite3_errmsg(db));
        chmod(KEYCHAIN_DB, 0600);
        sys_exec("launchctl load " SECD_PLIST " 2>/dev/null");
        return 1;
    }
    
    for (int i = 0; tables[i]; i++)
        before += count_from_table(db, tables[i], bundle_id);
    
    printf("Found %d items before\n", before);
    
    for (int i = 0; tables[i]; i++) {
        int d = delete_from_table(db, tables[i], bundle_id);
        if (d > 0) total += d;
    }
    
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", NULL, NULL, NULL);
    sqlite3_close(db);
    
    chmod(KEYCHAIN_DB, 0600);
    unlink(KEYCHAIN_WAL);
    unlink(KEYCHAIN_SHM);
    
    printf("Restarting securityd...\n");
    sys_exec("launchctl load " SECD_PLIST " 2>/dev/null");
    
    usleep(100000);
    chmod(KEYCHAIN_DB, 0644);
    sqlite3 *db2;
    if (sqlite3_open_v2(KEYCHAIN_DB, &db2, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        for (int i = 0; tables[i]; i++)
            after += count_from_table(db2, tables[i], bundle_id);
        sqlite3_close(db2);
    }
    chmod(KEYCHAIN_DB, 0600);
    
    FILE *rf = fopen(RESULT_FILE, "w");
    if (rf) {
        fprintf(rf, "Bundle ID: %s\nBefore: %d items\nDeleted: %d items\nRemaining: %d items\nStatus: %s\n",
            bundle_id, before, total, after,
            (after == 0) ? "OK - all cleared" : "WARNING - some remain");
        fclose(rf);
    }
    
    unlink(TRIGGER_FILE);
    printf("Done. %d -> %d deleted -> %d remain\n", before, total, after);
    return (after == 0) ? 0 : 1;
}
