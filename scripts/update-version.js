#!/usr/bin/env node

/**
 * Version Synchronization Script
 * Keeps docker-backup version in sync with locize-cli version
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const VERSION_FILE = '.locize-cli-version';
const PACKAGE_JSON = 'package.json';
const DOCKER_CLI_VERSION_FILE = '../docker-cli/.locize-cli-version';

/**
 * Read version from file
 */
function readVersionFile(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8').trim();
  } catch (error) {
    console.error(`Error reading ${filePath}:`, error.message);
    return null;
  }
}

/**
 * Write version to file
 */
function writeVersionFile(filePath, version) {
  try {
    fs.writeFileSync(filePath, version + '\n');
    console.log(`✅ Updated ${filePath} to version ${version}`);
    return true;
  } catch (error) {
    console.error(`Error writing ${filePath}:`, error.message);
    return false;
  }
}

/**
 * Update package.json version
 */
function updatePackageJson(version) {
  try {
    const packagePath = path.resolve(PACKAGE_JSON);
    const packageData = JSON.parse(fs.readFileSync(packagePath, 'utf8'));

    packageData.version = version;

    fs.writeFileSync(packagePath, JSON.stringify(packageData, null, 2) + '\n');
    console.log(`✅ Updated ${PACKAGE_JSON} to version ${version}`);
    return true;
  } catch (error) {
    console.error(`Error updating ${PACKAGE_JSON}:`, error.message);
    return false;
  }
}

/**
 * Fetch latest version from npm registry
 */
function fetchLatestVersionFromNpm() {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'registry.npmjs.org',
      path: '/locize-cli/latest',
      method: 'GET',
      headers: {
        'User-Agent': 'locize-backup-version-sync'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          const packageInfo = JSON.parse(data);
          resolve(packageInfo.version);
        } catch (error) {
          reject(new Error(`Failed to parse npm response: ${error.message}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to fetch from npm: ${error.message}`));
    });

    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    req.end();
  });
}

/**
 * Main synchronization function
 */
async function syncVersion() {
  console.log('🔄 Starting version synchronization...\n');

  // Check if we're in the docker-backup directory
  if (!fs.existsSync(PACKAGE_JSON)) {
    console.error('❌ package.json not found. Please run this script from the docker-backup directory.');
    process.exit(1);
  }

  let targetVersion = null;
  let source = '';

  // Try to get version from docker-cli first
  if (fs.existsSync(DOCKER_CLI_VERSION_FILE)) {
    targetVersion = readVersionFile(DOCKER_CLI_VERSION_FILE);
    source = 'docker-cli';
    console.log(`📋 Found docker-cli version: ${targetVersion}`);
  }

  // If no docker-cli version or force npm check, fetch from npm
  if (!targetVersion || process.argv.includes('--npm')) {
    try {
      console.log('🌐 Fetching latest version from npm registry...');
      targetVersion = await fetchLatestVersionFromNpm();
      source = 'npm registry';
      console.log(`📦 Latest npm version: ${targetVersion}`);
    } catch (error) {
      console.error(`❌ Failed to fetch from npm: ${error.message}`);
      if (!targetVersion) {
        process.exit(1);
      }
    }
  }

  if (!targetVersion) {
    console.error('❌ No version found from any source');
    process.exit(1);
  }

  // Read current version
  const currentVersion = readVersionFile(VERSION_FILE);
  console.log(`📌 Current version: ${currentVersion || 'not set'}`);

  // Check if update is needed
  if (currentVersion === targetVersion && !process.argv.includes('--force')) {
    console.log(`✅ Version is already up to date (${targetVersion})`);
    return;
  }

  console.log(`\n🔄 Updating from ${currentVersion || 'not set'} to ${targetVersion} (source: ${source})`);

  // Update version file
  if (!writeVersionFile(VERSION_FILE, targetVersion)) {
    process.exit(1);
  }

  // Update package.json
  if (!updatePackageJson(targetVersion)) {
    process.exit(1);
  }

  // Update docker-cli version file if we got version from npm
  if (source === 'npm registry' && fs.existsSync(path.dirname(DOCKER_CLI_VERSION_FILE))) {
    writeVersionFile(DOCKER_CLI_VERSION_FILE, targetVersion);
  }

  console.log(`\n✅ Version synchronization completed successfully!`);
  console.log(`📋 Project is now at locize-cli version: ${targetVersion}`);
  console.log(`\n💡 Next steps:`);
  console.log(`   - Run: npm run build`);
  console.log(`   - Run: npm run test:smoke`);
  console.log(`   - Commit changes: git add . && git commit -m "Update to locize-cli v${targetVersion}"`);
}

/**
 * Show help
 */
function showHelp() {
  console.log(`
Version Synchronization Script

Usage: node scripts/update-version.js [options]

Options:
  --npm     Force fetch from npm registry instead of docker-cli
  --force   Force update even if versions match
  --help    Show this help message

Examples:
  node scripts/update-version.js           # Sync from docker-cli or npm
  node scripts/update-version.js --npm     # Force sync from npm
  node scripts/update-version.js --force   # Force update
`);
}

// Handle command line arguments
if (process.argv.includes('--help')) {
  showHelp();
  process.exit(0);
}

// Run the sync
syncVersion().catch((error) => {
  console.error('❌ Synchronization failed:', error.message);
  process.exit(1);
});