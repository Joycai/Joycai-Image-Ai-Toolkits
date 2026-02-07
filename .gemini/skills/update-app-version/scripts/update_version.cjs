const fs = require('fs');
const path = require('path');

const targetVersion = process.argv[2];

if (!targetVersion) {
  console.error('Error: No target version provided.');
  process.exit(1);
}

// Basic semver-ish check (e.g., 1.2.3)
if (!/^\d+\.\d+\.\d+/.test(targetVersion)) {
  console.error('Error: Invalid version format. Expected something like 1.2.3');
  process.exit(1);
}

const rootDir = process.cwd();

const tasks = [
  {
    file: 'pubspec.yaml',
    regex: /^(\s*)version: .*/m,
    replace: `$1version: ${targetVersion}+1`,
  },
  {
    file: 'pubspec.yaml',
    regex: /^(\s*)msix_version: .*/m,
    replace: `$1msix_version: ${targetVersion}.0`,
  },
  {
    file: 'windows/runner/Runner.rc',
    regex: /#define VERSION_AS_STRING ".*"/,
    replace: `#define VERSION_AS_STRING "${targetVersion}"`,
  },
  {
    file: 'build_script/inno_setup.iss',
    regex: /#define MyAppVersion ".*"/,
    replace: `#define MyAppVersion "${targetVersion}"`,
  },
  {
    file: 'test/widget_test.dart',
    regex: /child: const MyApp\(version: '.*'\)/,
    replace: `child: const MyApp(version: '${targetVersion}')`,
  }
];

let updatedCount = 0;

tasks.forEach(task => {
  const filePath = path.join(rootDir, task.file);
  if (fs.existsSync(filePath)) {
    try {
      let content = fs.readFileSync(filePath, 'utf8');
      if (task.regex.test(content)) {
        content = content.replace(task.regex, task.replace);
        fs.writeFileSync(filePath, content, 'utf8');
        console.log(`Updated ${task.file}`);
        updatedCount++;
      } else {
        console.warn(`Warning: Pattern not found in ${task.file}`);
      }
    } catch (err) {
      console.error(`Error updating ${task.file}: ${err.message}`);
    }
  } else {
    console.warn(`Warning: File ${task.file} not found.`);
  }
});

console.log(`Successfully updated ${updatedCount} locations to version ${targetVersion}.`);
