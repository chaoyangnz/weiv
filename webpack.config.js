/* global __dirname, require, module*/

// const webpack = require('webpack');
const UglifyJsPlugin = require('uglifyjs-webpack-plugin');
const path = require('path');
const env = require('yargs').argv.env; // use --env with webpack 2

let libraryName = 'weiv';

let plugins = [], outputFile;

if (env === 'build') {
  plugins.push(new UglifyJsPlugin({ extractComments: true, sourceMap: false, parallel: 4 }));
  outputFile = libraryName + '.min.js';
} else {
  outputFile = libraryName + '.js';
}

const config = {
  entry: __dirname + '/src/index.js',
  devtool: 'source-map',
  output: {
    path: __dirname + '/lib',
    filename: outputFile,
    library: libraryName,
    libraryTarget: 'umd',
    umdNamedDefine: true
  },
  module: {
    rules: [
      {
        test: /(\.jsx|\.js)$/,
        loader: 'babel-loader',
        exclude: /(node_modules|bower_components)/
      },
      {
        test: /(\.jsx|\.js)$/,
        loader: 'eslint-loader',
        exclude: /node_modules/
      }
    ]
  },
  resolve: {
    modules: [path.resolve('./node_modules'), path.resolve('./src')],
    extensions: ['.json', '.js']
  },
  plugins: plugins
};

const appConfig = {
  entry: __dirname + '/example/app.js',
  devtool: 'source-map',
  output: {
    path: __dirname + '/example/dist',
    filename: 'app.js'
  },
  module: {
    rules: [
      {
        test: /(\.js)$/,
        loader: 'babel-loader',
        exclude: /(node_modules)/
      }
    ]
  },
  resolve: {
    modules: [path.resolve('./node_modules'), path.resolve('./src')],
    extensions: ['.json', '.js'],
    alias: {
      weivjs: path.resolve(__dirname, 'src/')
    }
  },
  plugins: plugins
};

let todoIndex;
if (env === 'build') {
  todoIndex = 'index.min.js';
} else {
  todoIndex = 'index.js';
}

const todomvcConfig = {
  entry: __dirname + '/todomvc/index.js',
  devtool: 'source-map',
  output: {
    path: __dirname + '/todomvc/dist',
    filename: todoIndex
  },
  module: {
    rules: [
      {
        test: /(\.js)$/,
        loader: 'babel-loader',
        exclude: /(node_modules)/
      }
    ]
  },
  resolve: {
    modules: [path.resolve('./node_modules'), path.resolve('./src')],
    extensions: ['.json', '.js'],
    alias: {
      weivjs: path.resolve(__dirname, 'src/')
    }
  },
  plugins: plugins
};

module.exports = [config, appConfig, todomvcConfig];
