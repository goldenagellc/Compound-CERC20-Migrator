const WBTCMigrator = artifacts.require("WBTCMigrator");

module.exports = (deployer, network, accounts) => {
  let lendingPoolAddressesProvider;
  let comptroller;

  switch (network) {
    case "ganache-fork":
    case "ganache":
    case "production-fork":
    case "production":
      lendingPoolAddressesProvider =
        "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5";
      comptroller = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
      break;
    default:
      console.error("Unknown network -- constructor args unspecified");
  }

  deployer.deploy(WBTCMigrator, lendingPoolAddressesProvider, comptroller, {
    from: accounts[0],
  });
};
