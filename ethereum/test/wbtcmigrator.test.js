const { assert, expect } = require("chai");
const Big = require("big.js");

let suppliers = require("./_suppliers.json");
const comptrollerabi = require("./_comptrollerabi.json");
const cwbtcv1abi = require("./_cwbtcv1abi.json");

const WBTCMigrator = artifacts.require("WBTCMigrator");

contract("WBTCMigrator Test", (accounts) => {
  web3.extend({
    methods: [
      {
        name: "mineImmediately",
        call: "evm_mine",
      },
      {
        name: "unlockUnknownAccount",
        call: "evm_unlockUnknownAccount",
        params: 1,
      },
    ],
  });

  const maxUINT256 = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";

  let wbtcMigrator;
  let comptroller;
  let cWBTCV1;

  let excludedSuppliers = new Set();
  let successCountMarketsEntered = 0;

  it("should approve for transfer", async () => {
    const promises = suppliers.map(async (supplier) => {
      const balance = Big(await web3.eth.getBalance(supplier));
      if (balance.lt("150000000000000000")) {
        excludedSuppliers.add(supplier);
        return;
      }

      await web3.unlockUnknownAccount(supplier);

      const method = cWBTCV1.methods.approve(wbtcMigrator.address, maxUINT256);
      const tx = method.send({ from: supplier });
      const receipt = await tx;

      assert.equal(receipt.status, 1);
    });

    await Promise.all(promises);
    console.log(
      `Skipping ${excludedSuppliers.size} out of ${suppliers.length} suppliers because they have insufficient ETH`
    );
  });

  it("should enter market", async () => {
    const promises = suppliers.map(async (supplier) => {
      if (excludedSuppliers.has(supplier)) return false;
      await web3.unlockUnknownAccount(supplier);

      try {
        const method = comptroller.methods.enterMarkets([
          "0xccf4429db6322d5c611ee964527d42e5d685dd6a",
        ]);
        const tx = method.send({ from: supplier });
        const receipt = await tx;

        assert.equal(receipt.status, 1);
        return receipt.status == 1;
      } catch (e) {
        console.log(e.message);
        excludedSuppliers.add(supplier);
        return false;
      }
    });

    const successes = await Promise.all(promises);
    successCountMarketsEntered = successes.reduce((a, b) => a + Number(b), 0);
    console.log(`Succeeded ${successCountMarketsEntered} times`);
  });

  it("should migrate", async () => {
    const promises = suppliers.map(async (supplier) => {
      if (excludedSuppliers.has(supplier)) return false;

      const tx = await wbtcMigrator.migrateWithExtraChecks(supplier, {
        from: supplier,
      });
      assert.equal(tx.receipt.status, 1);

      // if anything happened...
      if (tx.receipt.rawLogs.length > 0) {
        // then we expect a migration to have happened...
        numLogs = tx.receipt.rawLogs.length;
        assert.isTrue(numLogs == 27 || numLogs == 25);

        const migration = tx.receipt.logs[0];
        assert.equal(migration.logIndex, numLogs - 2);
        assert.equal(migration.event, "Migrated");
        assert.equal(migration.args.account, web3.utils.toChecksumAddress(supplier));

        const underlyingV1 = migration.args.underlyingV1.toNumber();
        const underlyingV2 = migration.args.underlyingV2.toNumber();
        assert.isTrue(Math.round(10000 * underlyingV2 / underlyingV1).toFixed(0) === "9991");
      }

      return tx.receipt.status == 1;
    });

    const successes = await Promise.all(promises);
    let successCount = successes.reduce((a, b) => a + Number(b), 0);
    assert.equal(successCount, successCountMarketsEntered);
    console.log(`Succeeded ${successCount} times`);
  });

  before(async () => {
    wbtcMigrator = await WBTCMigrator.deployed();
    comptroller = new web3.eth.Contract(
      comptrollerabi,
      "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b"
    );
    cWBTCV1 = new web3.eth.Contract(
      cwbtcv1abi,
      "0xc11b1268c1a384e55c48c2391d8d480264a3a7f4"
    );
  });
});
