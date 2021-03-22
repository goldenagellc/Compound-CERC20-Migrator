const WBTCMigrator = artifacts.require("WBTCMigrator");

module.exports = (deployer, network, accounts) => {
  let lendingPoolAddressesProvider;

  switch (network) {
    case "ganache-fork":
    case "ganache":
    case "production-fork":
    case "production":
      lendingPoolAddressesProvider =
        "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5";
      break;
    default:
      console.error("Unknown network -- constructor args unspecified");
  }

  deployer.deploy(WBTCMigrator, lendingPoolAddressesProvider, { from: accounts[0] });
};
