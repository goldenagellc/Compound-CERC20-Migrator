const { assert } = require("chai");
const Big = require("big.js");

let suppliers = require("./_suppliers.json");
suppliers = [suppliers[18]];
console.log(suppliers);
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
  let cWBTCV1;
  let excludedSuppliers = new Set();

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

  it("should migrate", async () => {
    const promises = suppliers.map(async (supplier) => {
      if (excludedSuppliers.has(supplier)) return true;

      const tx = await wbtcMigrator.migrateWithExtraChecks(supplier, { from: supplier });
      assert.equal(tx.receipt.status, 1);

      const events = tx.receipt.rawLogs;
      assert.isTrue(events.length == 25 || events.length == 23);

      return tx.receipt.status == 1
    });

    const successes = await Promise.all(promises);
    console.log(`Failed ${successes.reduce((a, b) => a + Number(!b), 0)} times`);
  });

  before(async () => {
    wbtcMigrator = await WBTCMigrator.deployed();
    cWBTCV1 = new web3.eth.Contract(
      cwbtcv1abi,
      "0xc11b1268c1a384e55c48c2391d8d480264a3a7f4"
    );
  });
});
