const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const projectRoot = __dirname;
// `react-native-card-detector` is installed from the parent folder via `file:..`.
// Make Metro watch the workspace root so it can resolve and reload the linked package.
const workspaceRoot = path.resolve(projectRoot, '..');

const config = {
  watchFolders: [workspaceRoot],
  resolver: {
    nodeModulesPaths: [
      path.resolve(projectRoot, 'node_modules'),
      path.resolve(workspaceRoot, 'node_modules')
    ]
  }
};

module.exports = mergeConfig(getDefaultConfig(projectRoot), config);
