#!/usr/bin/env node

const https = require('https');
const fs = require('fs');
const path = require('path');

/**
 * Fetches the latest version of ligouras/locize-cli Docker image from Docker Hub
 * @returns {Promise<string>} Latest version string
 */
function fetchLatestBaseImageVersion() {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'registry.hub.docker.com',
      path: '/v2/repositories/ligouras/locize-cli/tags/?page_size=100',
      method: 'GET',
      headers: {
        'User-Agent': 'locize-backup-docker-version-detector/1.0.0'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          if (!response.results || !Array.isArray(response.results)) {
            reject(new Error('Invalid response format from Docker Hub API'));
            return;
          }

          // Filter out 'latest' tag and find semantic versions
          const semverRegex = /^\d+\.\d+\.\d+(-[\w\.-]+)?(\+[\w\.-]+)?$/;
          const versions = response.results
            .map(tag => tag.name)
            .filter(name => name !== 'latest' && semverRegex.test(name))
            .sort((a, b) => compareVersions(b, a)); // Sort descending

          if (versions.length === 0) {
            reject(new Error('No valid semantic versions found for ligouras/locize-cli'));
            return;
          }

          const latestVersion = versions[0];
          console.log(`Found ${versions.length} versions, latest: ${latestVersion}`);
          resolve(latestVersion);

        } catch (error) {
          reject(new Error(`Failed to parse Docker Hub API response: ${error.message}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to fetch from Docker Hub API: ${error.message}`));
    });

    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error('Request to Docker Hub API timed out'));
    });

    req.end();
  });
}

/**
 * Validates that the base image version is available on Docker Hub
 * @param {string} version Version to validate
 * @returns {Promise<boolean>} True if version exists
 */
function validateBaseImageAvailability(version) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'registry.hub.docker.com',
      path: `/v2/repositories/ligouras/locize-cli/tags/${version}/`,
      method: 'GET',
      headers: {
        'User-Agent': 'locize-backup-docker-version-detector/1.0.0'
      }
    };

    const req = https.request(options, (res) => {
      if (res.statusCode === 200) {
        resolve(true);
      } else if (res.statusCode === 404) {
        resolve(false);
      } else {
        reject(new Error(`Unexpected status code ${res.statusCode} when validating base image`));
      }
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to validate base image availability: ${error.message}`));
    });

    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('Request to validate base image timed out'));
    });

    req.end();
  });
}

/**
 * Reads the current tracked base image version from file
 * @returns {string} Current version or '0.0.0' if file doesn't exist
 */
function readCurrentVersion() {
  const versionFile = path.join(process.cwd(), '.locize-cli-version');

  try {
    if (fs.existsSync(versionFile)) {
      const version = fs.readFileSync(versionFile, 'utf8').trim();

      // Validate the version format
      const semverRegex = /^\d+\.\d+\.\d+(-[\w\.-]+)?(\+[\w\.-]+)?$/;
      if (!semverRegex.test(version)) {
        console.warn(`Warning: Invalid version format in tracking file: ${version}. Using 0.0.0`);
        return '0.0.0';
      }

      return version;
    }
  } catch (error) {
    console.warn(`Warning: Failed to read version tracking file: ${error.message}. Using 0.0.0`);
  }

  return '0.0.0';
}

/**
 * Compares two semantic versions
 * @param {string} version1
 * @param {string} version2
 * @returns {number} -1 if version1 < version2, 0 if equal, 1 if version1 > version2
 */
function compareVersions(version1, version2) {
  // Handle pre-release versions by splitting on '-'
  const [v1Main, v1Pre] = version1.split('-');
  const [v2Main, v2Pre] = version2.split('-');

  const v1Parts = v1Main.split('.').map(Number);
  const v2Parts = v2Main.split('.').map(Number);

  // Compare main version numbers
  for (let i = 0; i < Math.max(v1Parts.length, v2Parts.length); i++) {
    const v1Part = v1Parts[i] || 0;
    const v2Part = v2Parts[i] || 0;

    if (v1Part < v2Part) return -1;
    if (v1Part > v2Part) return 1;
  }

  // If main versions are equal, handle pre-release versions
  if (v1Pre && !v2Pre) return -1; // v1 is pre-release, v2 is not
  if (!v1Pre && v2Pre) return 1;  // v2 is pre-release, v1 is not
  if (v1Pre && v2Pre) {
    return v1Pre.localeCompare(v2Pre); // Compare pre-release strings
  }

  return 0;
}

/**
 * Sets GitHub Actions output
 * @param {string} name Output name
 * @param {string} value Output value
 */
function setOutput(name, value) {
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
  } else {
    // Fallback for local testing
    console.log(`::set-output name=${name}::${value}`);
  }
}

/**
 * Main execution function
 */
async function main() {
  try {
    console.log('🔍 Detecting ligouras/locize-cli base image version changes...');

    // Fetch latest version from Docker Hub
    console.log('📡 Fetching latest base image version from Docker Hub...');
    const latestVersion = await fetchLatestBaseImageVersion();
    console.log(`✅ Latest base image version: ${latestVersion}`);

    // Validate base image availability
    console.log('🔍 Validating base image availability...');
    const isAvailable = await validateBaseImageAvailability(latestVersion);
    if (!isAvailable) {
      throw new Error(`Base image version ${latestVersion} is not available on Docker Hub`);
    }
    console.log(`✅ Base image version ${latestVersion} is available`);

    // Read current tracked version
    const currentVersion = readCurrentVersion();
    console.log(`📋 Current tracked base image version: ${currentVersion}`);

    // Determine if we should build
    let shouldBuild = false;
    const forceBuild = process.env.FORCE_BUILD === 'true' || process.argv.includes('--force');

    if (forceBuild) {
      console.log('🔨 Force build requested');
      shouldBuild = true;
    } else {
      const comparison = compareVersions(latestVersion, currentVersion);
      if (comparison > 0) {
        console.log(`🆕 Base image version changed from ${currentVersion} to ${latestVersion}`);
        shouldBuild = true;
      } else if (comparison === 0) {
        console.log('✅ No base image version change detected');
      } else {
        console.log(`⚠️  Warning: Latest base image version (${latestVersion}) is older than tracked version (${currentVersion})`);
      }
    }

    // Set GitHub Actions outputs
    setOutput('new_version', latestVersion);
    setOutput('current_version', currentVersion);
    setOutput('should_build', shouldBuild.toString());

    console.log(`📤 Outputs set:`);
    console.log(`   new_version: ${latestVersion}`);
    console.log(`   current_version: ${currentVersion}`);
    console.log(`   should_build: ${shouldBuild}`);

    // Exit with appropriate code
    process.exit(0);

  } catch (error) {
    console.error(`❌ Error: ${error.message}`);

    // Set error outputs for GitHub Actions
    setOutput('error', error.message);
    setOutput('should_build', 'false');

    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = {
  fetchLatestBaseImageVersion,
  validateBaseImageAvailability,
  readCurrentVersion,
  compareVersions
};