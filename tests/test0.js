const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const pointZeroOne = convert("0.01", 18);
const pointZeroTwo = convert("0.02", 18);
const pointOne = convert("0.1", 18);
const one = convert("1", 18);

function getRndInteger(min, max) {
  return Math.floor(Math.random() * (max - min)) + min;
}

let owner, treasury, user0, user1, user2, user3, faction0, faction1, faction2;
let base, voter, vaultFactory;
let plugin, multicall;

describe("local: test0", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    [
      owner,
      treasury,
      user0,
      user1,
      user2,
      user3,
      faction0,
      faction1,
      faction2,
    ] = await ethers.getSigners();

    const baseArtifact = await ethers.getContractFactory("Base");
    base = await baseArtifact.deploy();
    console.log("- Base Initialized");

    const voterArtifact = await ethers.getContractFactory("Voter");
    voter = await voterArtifact.deploy();
    console.log("- Voter Initialized");

    const vaultFactoryArtifact = await ethers.getContractFactory(
      "BerachainRewardVaultFactory"
    );
    vaultFactory = await vaultFactoryArtifact.deploy();
    console.log("- Vault Factory Initialized");

    const pluginArtifact = await ethers.getContractFactory("MapPlugin");
    plugin = await pluginArtifact.deploy(
      base.address,
      voter.address,
      [base.address],
      [base.address],
      treasury.address,
      treasury.address,
      vaultFactory.address
    );
    console.log("- Plugin Initialized");

    await voter.setPlugin(plugin.address);
    console.log("- System set up");

    const multicallArtifact = await ethers.getContractFactory("Multicall");
    multicall = await multicallArtifact.deploy(
      base.address,
      plugin.address,
      voter.address,
      await voter.OTOKEN()
    );
    console.log("- Multicall Initialized");

    console.log("Initialization Complete");
    console.log();
  });

  it("First test", async function () {
    console.log("******************************************************");
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await multicall.connect(user0).composeFor(user0.address, [0], [1], {
      value: pointZeroOne,
    });
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tiles in first row", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user1.getBalance()));
    await multicall
      .connect(user1)
      .composeFor(
        user1.address,
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
        {
          value: pointOne,
        }
      );
    console.log("ETH balance: ", divDec(await user1.getBalance()));
  });

  it("Gauge data", async function () {
    console.log("******************************************************");
    console.log(await multicall.getGauge(user0.address));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const res = await multicall.getSlots(0, 1); // Fetch 100 pixels for a 10x10 grid
    console.log(res);
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("Get Pixels", async function () {
    console.log("******************************************************");
    console.log(await plugin.getSlot(0));
    console.log(await plugin.getSlot(1));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await multicall.connect(user0).composeFor(user0.address, [0], [1], {
      value: pointZeroOne,
    });
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await multicall.connect(user0).composeFor(user0.address, [0], [1], {
      value: pointZeroOne,
    });
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await multicall.connect(user0).composeFor(user0.address, [0], [125], {
      value: pointZeroOne,
    });
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Get Account State", async function () {
    console.log("******************************************************");
    console.log(await multicall.getAccountState(user0.address));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await multicall.connect(user0).composeFor(user0.address, [0, 1], [2, 3], {
      value: pointZeroTwo,
    });
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    await expect(
      multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
          [10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
          {
            value: pointZeroOne,
          }
        )
    ).to.be.reverted;
    await multicall
      .connect(user0)
      .composeFor(
        user0.address,
        [10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
        [10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
        {
          value: pointOne,
        }
      );
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1322342)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1322342)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1322342)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1322342)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1322342)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("Get Account State", async function () {
    console.log("******************************************************");
    console.log(await multicall.getAccountState(user0.address));
  });

  it("Gauge data", async function () {
    console.log("******************************************************");
    console.log(await multicall.getGauge(user0.address));
  });

  it("Gauge data", async function () {
    console.log("******************************************************");
    console.log(await multicall.getGauge(user1.address));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));

    it("User2 places tile", async function () {
      console.log("******************************************************");
      console.log("ETH balance: ", divDec(await user0.getBalance()));
      for (let i = 0; i < 100; i++) {
        await multicall
          .connect(user2)
          .composeFor(
            user2.address,
            [getRndInteger(0, 100)],
            [getRndInteger(1, 13242)],
            {
              value: pointZeroOne,
            }
          );
      }
      console.log("ETH balance: ", divDec(await user0.getBalance()));
    });
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 13242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [getRndInteger(1, 3)],
          [getRndInteger(0, 100)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user0.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user2.address,
          [getRndInteger(0, 100)],
          [getRndInteger(1, 1332234242)],
          {
            value: pointZeroOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 99); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 10; col++) {
        const pixelIndex = row * 10 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("User0 places tiles in first row", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user1.getBalance()));
    await multicall
      .connect(user0)
      .composeFor(
        user0.address,
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
        {
          value: pointOne,
        }
      );
    console.log("ETH balance: ", divDec(await user1.getBalance()));
  });

  it("User1 places tiles in first row", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user1.getBalance()));
    await multicall
      .connect(user1)
      .composeFor(
        user1.address,
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
        {
          value: pointOne,
        }
      );
    console.log("ETH balance: ", divDec(await user1.getBalance()));
  });

  it("User2 places tiles in first row", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user1.getBalance()));
    await multicall
      .connect(user2)
      .composeFor(
        user2.address,
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
        {
          value: pointOne,
        }
      );
    console.log("ETH balance: ", divDec(await user1.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Increase Capacity", async function () {
    console.log("******************************************************");
    await expect(plugin.setCapacity(50)).to.be.revertedWith(
      "Plugin__InvalidCapacity()"
    );
    await plugin.setCapacity(200);
  });

  it("Grid data velocities", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 199); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 20; col++) {
        const pixelIndex = row * 20 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user0)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User0 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user0.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User1 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user1)
        .composeFor(
          user1.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("User2 places tile", async function () {
    console.log("******************************************************");
    console.log("ETH balance: ", divDec(await user0.getBalance()));
    for (let i = 0; i < 100; i++) {
      await multicall
        .connect(user2)
        .composeFor(
          user2.address,
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
          [4, 23, 4, 43, 4, 0, 0, 4, 4, 4],
          {
            value: pointOne,
          }
        );
    }
    console.log("ETH balance: ", divDec(await user0.getBalance()));
  });

  it("Grid data Velocities", async function () {
    console.log("******************************************************");
    const gridChunk = await multicall.getSlots(0, 199); // Fetch 100 pixels for a 10x10 grid
    // Visualize the grid
    console.log("Grid Visualization:");
    for (let row = 0; row < 10; row++) {
      let rowVelocities = [];
      for (let col = 0; col < 20; col++) {
        const pixelIndex = row * 20 + col;
        const pixel = gridChunk[pixelIndex];
        rowVelocities.push(pixel.velocity.toString());
      }
      console.log(rowVelocities.join(" "));
    }
  });
});
