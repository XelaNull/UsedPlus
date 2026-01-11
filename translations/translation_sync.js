#!/usr/bin/env node
/**
 * Translation Sync Tool for FS25_UsedPlus
 * ========================================
 * Manages versioning of translation entries using English source hashes.
 *
 * Commands:
 *   node translation_sync.js stamp    - Add/update hashes to all translation files
 *   node translation_sync.js check    - Check which entries are out of sync
 *   node translation_sync.js report   - Generate detailed sync report
 *
 * The 'eh' (English hash) attribute stores an 8-char hash of the English source text.
 * When English text changes, the hash won't match, indicating the translation needs updating.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const LANGUAGES = ['de', 'fr', 'es', 'it', 'pl', 'ru', 'br', 'cz', 'uk'];
const LANG_NAMES = {
    de: 'German', fr: 'French', es: 'Spanish', it: 'Italian',
    pl: 'Polish', ru: 'Russian', br: 'Portuguese', cz: 'Czech', uk: 'Ukrainian'
};

// Change to script directory
process.chdir(__dirname);

/**
 * Generate 8-character MD5 hash of text.
 */
function getHash(text) {
    return crypto.createHash('md5').update(text, 'utf8').digest('hex').substring(0, 8);
}

/**
 * Load English source strings and their hashes.
 */
function loadEnglishStrings() {
    const content = fs.readFileSync('translation_en.xml', 'utf8');
    const strings = {};

    // Match all <e k="key" v="value" /> entries
    const pattern = /<e k="([^"]+)" v="([^"]*)"[^/]*\/>/g;
    let match;

    while ((match = pattern.exec(content)) !== null) {
        const key = match[1];
        const value = match[2];
        strings[key] = { value, hash: getHash(value) };
    }

    return strings;
}

/**
 * Escape special regex characters in a string.
 */
function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Add/update English hashes to all translation files.
 */
function stampTranslations() {
    console.log("Stamping translation files with English hashes...\n");

    const enStrings = loadEnglishStrings();

    for (const lang of LANGUAGES) {
        const filepath = `translation_${lang}.xml`;

        if (!fs.existsSync(filepath)) {
            console.log(`  ${lang.toUpperCase()}: File not found, skipping`);
            continue;
        }

        let content = fs.readFileSync(filepath, 'utf8');
        let updated = 0;
        let added = 0;

        for (const [key, data] of Object.entries(enStrings)) {
            const eh = data.hash;

            // Pattern to match the entry with or without eh attribute
            const pattern = new RegExp(
                `<e k="${escapeRegex(key)}" v="([^"]*)"(\\s+eh="[^"]*")?\\s*/>`,
                'g'
            );

            content = content.replace(pattern, (match, v, oldEh) => {
                if (oldEh) {
                    updated++;
                } else {
                    added++;
                }
                return `<e k="${key}" v="${v}" eh="${eh}" />`;
            });
        }

        fs.writeFileSync(filepath, content, 'utf8');

        const langName = LANG_NAMES[lang].padEnd(12);
        console.log(`  ${langName}: ${added} hashes added, ${updated} updated`);
    }

    console.log("\nDone! All translation files now have English hashes.");
}

/**
 * Check which entries are out of sync.
 */
function checkSync() {
    console.log("Checking translation sync status...\n");

    const enStrings = loadEnglishStrings();
    let totalOutOfSync = 0;

    for (const lang of LANGUAGES) {
        const filepath = `translation_${lang}.xml`;

        if (!fs.existsSync(filepath)) {
            continue;
        }

        const content = fs.readFileSync(filepath, 'utf8');
        const outOfSync = [];
        const missingHash = [];

        // Find all entries with eh attribute
        const patternWithEh = /<e k="([^"]+)" v="[^"]*" eh="([^"]*)" \/>/g;
        let match;

        while ((match = patternWithEh.exec(content)) !== null) {
            const key = match[1];
            const storedHash = match[2];

            if (enStrings[key]) {
                const currentHash = enStrings[key].hash;
                if (storedHash !== currentHash) {
                    outOfSync.push(key);
                }
            }
        }

        // Find entries without eh attribute
        const patternNoEh = /<e k="([^"]+)" v="[^"]*" \/>/g;
        while ((match = patternNoEh.exec(content)) !== null) {
            const key = match[1];
            if (enStrings[key]) {
                missingHash.push(key);
            }
        }

        const status = outOfSync.length === 0 ? "OK" : "NEEDS UPDATE";
        const langName = LANG_NAMES[lang].padEnd(12);
        console.log(`  ${langName}: ${status}`);

        if (outOfSync.length > 0) {
            console.log(`    Out of sync (${outOfSync.length}):`);
            for (const key of outOfSync.slice(0, 5)) {
                console.log(`      - ${key}`);
            }
            if (outOfSync.length > 5) {
                console.log(`      ... and ${outOfSync.length - 5} more`);
            }
            totalOutOfSync += outOfSync.length;
        }

        if (missingHash.length > 0) {
            console.log(`    Missing hash (${missingHash.length}): run 'stamp' command`);
        }
    }

    console.log();
    if (totalOutOfSync === 0) {
        console.log("All translations are in sync!");
    } else {
        console.log(`Total out of sync: ${totalOutOfSync} entries need re-translation`);
    }
}

/**
 * Generate detailed sync report.
 */
function generateReport() {
    console.log("=".repeat(60));
    console.log("TRANSLATION SYNC REPORT");
    console.log("=".repeat(60));
    console.log();

    const enStrings = loadEnglishStrings();
    console.log(`English source: ${Object.keys(enStrings).length} strings\n`);

    for (const lang of LANGUAGES) {
        const filepath = `translation_${lang}.xml`;

        if (!fs.existsSync(filepath)) {
            continue;
        }

        const content = fs.readFileSync(filepath, 'utf8');
        const inSync = [];
        const outOfSync = [];
        const missingHash = [];
        const untranslated = [];

        // Check all entries
        for (const [key, data] of Object.entries(enStrings)) {
            // Look for entry with hash
            const patternWithEh = new RegExp(
                `<e k="${escapeRegex(key)}" v="([^"]*)" eh="([^"]*)" />`,
                ''
            );
            let match = content.match(patternWithEh);

            if (match) {
                const v = match[1];
                const storedHash = match[2];
                const currentHash = data.hash;

                if (v === data.value) {
                    untranslated.push(key);
                } else if (storedHash === currentHash) {
                    inSync.push(key);
                } else {
                    outOfSync.push({ key, enValue: data.value });
                }
            } else {
                // Look for entry without hash
                const patternNoEh = new RegExp(
                    `<e k="${escapeRegex(key)}" v="([^"]*)" />`,
                    ''
                );
                match = content.match(patternNoEh);

                if (match) {
                    const v = match[1];
                    if (v === data.value) {
                        untranslated.push(key);
                    } else {
                        missingHash.push(key);
                    }
                }
            }
        }

        console.log(`${LANG_NAMES[lang]} (${lang.toUpperCase()}):`);
        console.log(`  In sync:      ${inSync.length}`);
        console.log(`  Out of sync:  ${outOfSync.length}`);
        console.log(`  Missing hash: ${missingHash.length}`);
        console.log(`  Untranslated: ${untranslated.length}`);

        if (outOfSync.length > 0) {
            console.log(`  --- Out of sync entries (need re-translation) ---`);
            for (const { key, enValue } of outOfSync.slice(0, 10)) {
                console.log(`    ${key}:`);
                const truncated = enValue.length > 50 ? enValue.substring(0, 50) + '...' : enValue;
                console.log(`      EN: ${truncated}`);
            }
            if (outOfSync.length > 10) {
                console.log(`    ... and ${outOfSync.length - 10} more`);
            }
        }
        console.log();
    }

    console.log("=".repeat(60));
    console.log("Run 'node translation_sync.js stamp' to update all hashes");
    console.log("=".repeat(60));
}

/**
 * Show help text.
 */
function showHelp() {
    console.log(`
Translation Sync Tool for FS25_UsedPlus
========================================
Manages versioning of translation entries using English source hashes.

Commands:
  node translation_sync.js stamp    - Add/update hashes to all translation files
  node translation_sync.js check    - Check which entries are out of sync
  node translation_sync.js report   - Generate detailed sync report

The 'eh' (English hash) attribute stores an 8-char hash of the English source text.
When English text changes, the hash won't match, indicating the translation needs updating.
`);
}

// Main
const command = process.argv[2]?.toLowerCase();

switch (command) {
    case 'stamp':
        stampTranslations();
        break;
    case 'check':
        checkSync();
        break;
    case 'report':
        generateReport();
        break;
    default:
        showHelp();
}
