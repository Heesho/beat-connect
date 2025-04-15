// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMapPlugin {
    struct Slot {
        address account;
        uint256 velocity;
    }
    function composeFor(address account, uint256[] calldata indexes, uint256[] calldata velocities) external;
    function getGauge() external view returns (address);
    function composePrice() external view returns (uint256);
    function getSlot(uint256 index) external view returns (Slot memory);
    function getSlots(uint256 startIndex, uint256 endIndex) external view returns (Slot[] memory);
    function account_Composed(address account) external view returns (uint256);
}

interface IGauge {
    function totalSupply() external view returns (uint256);
    function getRewardForDuration(address token) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account, address token) external view returns (uint256);
    function getReward(address account) external;
}

interface IWBERA {
    function deposit() external payable;
}

contract Multicall {
    using SafeERC20 for IERC20;

    address public immutable base;
    address public immutable plugin;
    address public immutable voter;
    address public immutable oBERO;

    struct AccountState {
        uint256 balance;
        uint256 composed;
    }

    struct GaugeState {
        uint256 rewardPerToken;
        uint256 totalSupply;
        uint256 balance;
        uint256 earned;
        uint256 oBeroBalance;
    }

    constructor(address _base, address _plugin, address _voter, address _oBERO) {
        base = _base;
        plugin = _plugin;
        voter = _voter;
        oBERO = _oBERO;
    }

    function composeFor(address account, uint256[] calldata indexes, uint256[] calldata velocities) external payable {
        IWBERA(base).deposit{value: msg.value}();
        IERC20(base).safeApprove(plugin, 0);
        IERC20(base).safeApprove(plugin, msg.value);
        IMapPlugin(plugin).composeFor(account, indexes, velocities);
    }

    function getReward(address account) external {
        IGauge(IMapPlugin(plugin).getGauge()).getReward(account);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function getComposePrice() external view returns (uint256) {
        return IMapPlugin(plugin).composePrice();
    }

    function getGauge(address account) external view returns (GaugeState memory gaugeState) {
        address gauge = IMapPlugin(plugin).getGauge();
        gaugeState.rewardPerToken = IGauge(gauge).totalSupply() == 0 ? 0 : (IGauge(gauge).getRewardForDuration(oBERO) * 1e18 / IGauge(gauge).totalSupply());
        gaugeState.totalSupply = IGauge(gauge).totalSupply();
        gaugeState.balance = IGauge(gauge).balanceOf(account);
        gaugeState.earned = IGauge(gauge).earned(account, oBERO);
        gaugeState.oBeroBalance = IERC20(oBERO).balanceOf(account);
    }

    function getAccountState(address account) external view returns (AccountState memory accountState) {
        address gauge = IMapPlugin(plugin).getGauge();
        accountState.balance = IGauge(gauge).balanceOf(account);
        accountState.composed = IMapPlugin(plugin).account_Composed(account);
    }

    function getSlot(uint256 index) external view returns (IMapPlugin.Slot memory) {
        return IMapPlugin(plugin).getSlot(index);
    }

    function getSlots(uint256 startIndex, uint256 endIndex) external view returns (IMapPlugin.Slot[] memory) {
        return IMapPlugin(plugin).getSlots(startIndex, endIndex);
    }

}