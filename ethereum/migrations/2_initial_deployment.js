const CERC20Migrator = artifacts.require("CERC20Migrator");

module.exports = (deployer, network, accounts) => {
  let LENDINGPOOLADDRESSESPROVIDER;
  let COMPTROLLER;
  let CTOKENV1;
  let CTOKENV2;

  switch (network) {
    case "ganache-fork":
    case "ganache":
    case "production-fork":
    case "production":
      LENDINGPOOLADDRESSESPROVIDER =
        "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5";
      COMPTROLLER = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
      CTOKENV1 = "0xC11b1268C1A384e55C48c2391d8d480264A3A7F4";
      CTOKENV2 = "0xccF4429DB6322D5C611ee964527D42E5d685DD6a";
      break;
    default:
      console.error("Unknown network -- constructor args unspecified");
  }

  deployer.deploy(
    CERC20Migrator,
    LENDINGPOOLADDRESSESPROVIDER,
    COMPTROLLER,
    CTOKENV1,
    CTOKENV2,
    {
      from: accounts[0],
    }
  );
};
