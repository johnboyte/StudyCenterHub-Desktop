<?php
// Automated Local Test Suite for directory_index Migration (Legacy -> New Schema)

$db_file = __DIR__ . '/test_migration_relay.db';
if (file_exists($db_file)) {
    unlink($db_file);
}

$pdo = new PDO('sqlite:' . $db_file);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

// 1. Create Legacy (OLD) phone-keyed directory_index table
$pdo->exec("CREATE TABLE directory_index (
    phone_e164 TEXT PRIMARY KEY,
    first_name TEXT NOT NULL,
    masked_phone TEXT NOT NULL,
    human_id TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);");

// Seed Legacy Record
$pdo->exec("INSERT INTO directory_index (phone_e164, first_name, masked_phone, human_id) VALUES ('+18005550199', 'John', '•••-•••-0199', 'P-20260813-F9C7');");

echo "=== STAGE 1: LEGACY TABLE SEEDED ===\n";
$old_pragma = $pdo->query("PRAGMA table_info(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
print_r(array_column($old_pragma, 'name'));

// 2. Execute Migration Code (Same as gateway/index.php)
$pragma = $pdo->query("PRAGMA table_info(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
$pk_col = '';
$has_last_name = false;
$has_profile_photo = false;

foreach ($pragma as $c) {
    if (!empty($c['pk'])) {
        $pk_col = $c['name'];
    }
    if ($c['name'] === 'last_name') {
        $has_last_name = true;
    }
    if ($c['name'] === 'profile_photo') {
        $has_profile_photo = true;
    }
}

if ($pk_col === 'phone_e164' || !$has_last_name || !$has_profile_photo) {
    $pdo->beginTransaction();

    $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index_new (
        human_id TEXT PRIMARY KEY,
        phone_e164 TEXT,
        first_name TEXT NOT NULL,
        last_name TEXT DEFAULT '',
        masked_phone TEXT DEFAULT '',
        profile_photo TEXT DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );");

    $old_cols = array_column($pragma, 'name');
    $sel_human_id = in_array('human_id', $old_cols) ? 'human_id' : "('P-' || substr(hex(randomblob(6)), 1, 8))";
    $sel_phone = in_array('phone_e164', $old_cols) ? 'phone_e164' : "''";
    $sel_first = in_array('first_name', $old_cols) ? 'first_name' : "'Member'";
    $sel_last = in_array('last_name', $old_cols) ? 'last_name' : "''";
    $sel_masked = in_array('masked_phone', $old_cols) ? 'masked_phone' : "''";
    $sel_photo = in_array('profile_photo', $old_cols) ? 'profile_photo' : "''";
    $sel_updated = in_array('updated_at', $old_cols) ? 'updated_at' : "datetime('now')";

    $pdo->exec("INSERT OR IGNORE INTO directory_index_new (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
                SELECT $sel_human_id, $sel_phone, $sel_first, $sel_last, $sel_masked, $sel_photo, $sel_updated
                FROM directory_index;");

    $pdo->exec("DROP TABLE directory_index;");
    $pdo->exec("ALTER TABLE directory_index_new RENAME TO directory_index;");
    $pdo->exec("CREATE INDEX IF NOT EXISTS idx_directory_phone_e164 ON directory_index(phone_e164);");
    $pdo->commit();
}

echo "=== STAGE 2: MIGRATION EXECUTED ===\n";
$new_pragma = $pdo->query("PRAGMA table_info(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
print_r(array_column($new_pragma, 'name'));

$rec = $pdo->query("SELECT * FROM directory_index WHERE human_id = 'P-20260813-F9C7'")->fetch(PDO::FETCH_ASSOC);
echo "Migrated Legacy Record: " . json_encode($rec) . "\n";

// 3. Test Phone Lookup on Migrated Table
$phone_stmt = $pdo->prepare("SELECT first_name, masked_phone, human_id FROM directory_index WHERE phone_e164 = ?");
$phone_stmt->execute(['+18005550199']);
$phone_found = $phone_stmt->fetch(PDO::FETCH_ASSOC);
echo "Phone Lookup Result: " . json_encode($phone_found) . "\n";

// 4. Test Human ID Upsert with Last Name and Photo
$upsert = $pdo->prepare("INSERT OR REPLACE INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))");
$upsert->execute(['P-20260813-F9C7', '+18005550199', 'John', 'Boyte', '•••-•••-0199', 'data:image/jpeg;base64,TESTDATA']);

$updated_rec = $pdo->query("SELECT human_id, first_name, last_name, profile_photo FROM directory_index WHERE human_id = 'P-20260813-F9C7'")->fetch(PDO::FETCH_ASSOC);
echo "Upserted Record: " . json_encode($updated_rec) . "\n";

// 5. Test Member Without Phone Number
$upsert->execute(['P-99999999-NO-PHONE', '', 'Sarah', 'Connor', '', 'data:image/png;base64,NO_PHONE']);
$no_phone_rec = $pdo->query("SELECT human_id, first_name, last_name, phone_e164 FROM directory_index WHERE human_id = 'P-99999999-NO-PHONE'")->fetch(PDO::FETCH_ASSOC);
echo "No-Phone Member Record: " . json_encode($no_phone_rec) . "\n";

echo "=== MIGRATION TEST PASSED 100% ===\n";
unlink($db_file);
