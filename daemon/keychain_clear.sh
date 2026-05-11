#!/cores/binpack/bin/sh
export PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/cores/binpack/bin:/usr/bin:/bin:/usr/sbin:/sbin

DB=/private/var/Keychains/keychain-2.db
WAL=/private/var/Keychains/keychain-2.db-wal
SHM=/private/var/Keychains/keychain-2.db-shm
TRIGGER=/var/jb/var/keychain_cleaner/trigger
RESULT=/var/jb/var/keychain_cleaner/result
SECD=/System/Library/LaunchDaemons/com.apple.securityd.plist

if [ ! -f "$TRIGGER" ]; then
  echo "No trigger file" >&2
  exit 1
fi

BID=$(head -1 "$TRIGGER" | sed "s/[^a-zA-Z0-9._-]//g")
if [ -z "$BID" ]; then
  echo "Empty bundle ID" >&2
  exit 1
fi

echo "Clearing keychain for: $BID"

launchctl unload "$SECD" 2>/dev/null
sleep 0.5

chmod 644 "$DB"

COUNT_BEFORE=0
for t in genp keys; do
  c=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $t WHERE agrp LIKE \"%$BID%\";" 2>/dev/null)
  COUNT_BEFORE=$((COUNT_BEFORE + ${c:-0}))
done

sqlite3 "$DB" "DELETE FROM genp WHERE agrp LIKE \"%$BID%\";" 2>/dev/null
sqlite3 "$DB" "DELETE FROM inet WHERE agrp LIKE \"%$BID%\";" 2>/dev/null
sqlite3 "$DB" "DELETE FROM cert WHERE agrp LIKE \"%$BID%\";" 2>/dev/null
sqlite3 "$DB" "DELETE FROM keys WHERE agrp LIKE \"%$BID%\";" 2>/dev/null

chmod 600 "$DB"
rm -f "$WAL" "$SHM"

launchctl load "$SECD" 2>/dev/null
sleep 0.3

chmod 644 "$DB"
COUNT_AFTER=0
for t in genp keys; do
  c=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $t WHERE agrp LIKE \"%$BID%\";" 2>/dev/null)
  COUNT_AFTER=$((COUNT_AFTER + ${c:-0}))
done
chmod 600 "$DB"

{
  echo "Bundle ID: $BID"
  echo "Before: $COUNT_BEFORE items"
  echo "Remaining: $COUNT_AFTER items"
  if [ "$COUNT_AFTER" = "0" ]; then
    echo "Status: OK - all cleared"
  else
    echo "Status: WARNING - some remain"
  fi
} > "$RESULT"

rm -f "$TRIGGER"
echo "Done. $COUNT_BEFORE -> $COUNT_AFTER remain"
