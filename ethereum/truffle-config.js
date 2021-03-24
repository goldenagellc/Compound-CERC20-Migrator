require("dotenv-safe").config({
  example: process.env.CI ? ".env.ci.example" : ".env.example",
});
const ganache = require("ganache-cli");
const HDWalletProvider = require("@truffle/hdwallet-provider");
const { ProviderFor } = require("./providers");

const mainnet_ws = ProviderFor(
  "mainnet",
  process.env.CI
    ? {
        type: "WS_Infura",
        envKeyID: "PROVIDER_INFURA_ID",
      }
    : {
        type: "IPC",
        envKeyPath: "PROVIDER_IPC_PATH",
      }
);
const maxUINT256 = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";

const ganacheServerConfig = {
  fork: mainnet_ws,
  accounts: [{ balance: maxUINT256 }],
  ws: true,
};

// Start ganache server. Sometimes it won't get used, but this seems to be the
// only place it can be put and function correctly
const ganacheServer = ganache.server(ganacheServerConfig);
ganacheServer.listen(8547, "127.0.0.1");

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    ganache: {
      port: 8547,
      host: "127.0.0.1",
      network_id: "*",
    },

    production: {
      provider: () =>
        new HDWalletProvider(
          [process.env.ACCOUNT_SECRET_DEPLOY],
          "https://mainnet.infura.io/v3/" + process.env.PROVIDER_INFURA_ID
        ),
      network_id: "1",
      gasPrice: 140e9,
      gas: 3500000,
    },
  },

  mocha: {},

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.0", // Fetch exact version from solc-bin (default: truffle's version)
      docker: false, // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {
        // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 1337,
        },
        evmVersion: "byzantium",
      },
    },
  },
};
