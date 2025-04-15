// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev Interface for a Gauge contract in Beradrome, enabling deposits/withdrawals
 *      that track each user's balance for distributing oBERO rewards.
 */
interface IGauge {
    function _deposit(address account, uint256 amount) external;
    function _withdraw(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @dev Interface for a Bribe contract in Beradrome, enabling reward notifications
 *      for hiBERO voters.
 */
interface IBribe {
    function notifyRewardAmount(address token, uint amount) external;
}

/**
 * @dev Interface to the Voter contract that references an OTOKEN address.
 */
interface IVoter {
    function OTOKEN() external view returns (address);
}

/**
 * @dev Factory interface to create a specialized RewardVault for a given vault token.
 *      This vault integrates with Berachain's Proof-of-Liquidity (PoL) system.
 */
interface IBerachainRewardVaultFactory {
    function createRewardVault(address _vaultToken) external returns (address);
}

/**
 * @dev RewardVault interface for delegating stake and withdrawing it,
 *      thereby enabling the user to earn BGT from the PoL.
 */
interface IRewardVault {
    function delegateStake(address account, uint256 amount) external;
    function delegateWithdraw(address account, uint256 amount) external;
}

/**
 * @title VaultToken
 * @notice This is a simple ERC20 token used by the MapPlugin to represent staked positions.
 *         Whenever a user composes notes, an equivalent amount of VaultToken is minted and
 *         staked into the RewardVault. When notes are overwritten, these tokens are burned.
 */
contract VaultToken is ERC20, Ownable {
    /**
     * @notice Initializes the ERC20 with a name ("BeatConnect") and symbol ("BEAT").
     */
    constructor() ERC20("BeatConnect", "BEAT") {}

    /**
     * @dev Mints `amount` tokens to the `to` address. Restricted to the contract owner (MapPlugin).
     * @param to Address to receive the minted tokens.
     * @param amount Number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns `amount` tokens from the `from` address. Restricted to the contract owner (MapPlugin).
     * @param from Address to burn tokens from.
     * @param amount Number of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

/**
 * @title MapPlugin
 * @notice This contract represents the BeatConnect music sequencer as a Beradrome plugin.
 *         - Users compose music by setting note velocities in slots
 *         - Each slot can have a velocity from 0 (off) to 127 (max intensity)
 *         - Staking logic is handled via a Gauge and a specialized RewardVault
 *         - The contract distributes fees for bribes, treasury, and development
 */
contract MapPlugin is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    /**
     * @dev DURATION is used as a threshold for deciding when to perform claim/distribute operations.
     */
    uint256 public constant DURATION = 7 days;
    /**
     * @dev Each composed note in the grid increments the staked amount by 1 (AMOUNT = 1).
     *      This represents a single note placement in the sequencer.
     */
    uint256 public constant AMOUNT = 1;

    /**
     * @notice Display strings to identify the plugin's protocol and name.
     */
    string public constant PROTOCOL = "BabyBera";
    string public constant NAME = "Beat Connect";  

    /*----------  STATE VARIABLES  --------------------------------------*/

    /**
     * @notice The ERC20 token used to pay for composing music (likely WBERA).
     */
    IERC20 private immutable token;
    /**
     * @notice Address of the "oTOKEN" pulled from the Voter contract.
     *         Used to track which reward token is distributed from the gauge.
     */
    address private immutable OTOKEN;
    /**
     * @notice The Beradrome Voter contract address.
     *         Needed for restricted calls like setGauge/setBribe.
     */
    address private immutable voter;
    /**
     * @notice The gauge contract address where staked amounts (notes) earn oBERO rewards.
     */
    address private gauge;
    /**
     * @notice The bribe contract address for distributing bribes to hiBERO voters.
     */
    address private bribe;

    /**
     * @notice The VaultToken contract used to represent staked positions (minted/burned on note composition/overwrite).
     */
    address private vaultToken;
    /**
     * @notice A specialized RewardVault contract created by the vault factory,
     *         enabling delegation of stake to earn BGT (PoL integration).
     */
    address private rewardVault;

    /**
     * @notice Asset tokens associated with this plugin. Typically just [WBERA].
     */
    address[] private assetTokens;
    /**
     * @notice Bribe tokens associated with this plugin. Typically just [WBERA].
     */
    address[] private bribeTokens;

    /**
     * @notice The treasury address receives a portion of the fees.
     */
    address public treasury;
    /**
     * @notice The developer address receives a portion of the fees.
     */
    address public developer;
    /**
     * @notice The incentives address receives a portion of the fees.
     */
    address public incentives;
    /**
     * @notice The maximum index allowed for composing notes (initially 100, can be extended).
     *         If `capacity = 100`, valid slot indexes are from 0 to 99, for instance.
     */
    uint256 public capacity = 100;
    /**
     * @notice The cost to compose a single note in BERA terms.
     */
    uint256 public composePrice = 0.01 ether;
    /**
     * @notice The total number of notes composed.
     *         Summation of all composed notes across all addresses.
     */
    uint256 public totalComposed;
    /**
     * @notice Whether bribe distribution is automatically handled by the contract.
     *         If true, the majority of fees are directly sent to the bribe contract.
     */
    bool public activeBribes = true;
    /**
     * @notice Whether incentives are active.
     */
    bool public activeIncentives = false;

    /**
     * @notice Represents a single slot on the grid.
     * @param account The user who currently owns/composed this slot.
     * @param velocity The velocity of the slot.
     */
    struct Slot {
        address account;
        uint256 velocity;
    }

    /**
     * @notice index => Slot data. 
     *         Where index is the slot ID (0..capacity-1).
     */
    mapping(uint256 => Slot) public index_Slot;

    /**
     * @notice Maps each address to the total number of notes they have composed.
     */
    mapping(address => uint256) public account_Composed;

    /*----------  ERRORS ------------------------------------------------*/

    error Plugin__InvalidIndex();
    error Plugin__InvalidZeroInput();
    error Plugin__InvalidLength();
    error Plugin__InvalidZeroAddress();
    error Plugin__NotAuthorizedDeveloper();
    error Plugin__NotAuthorizedVoter();
    error Plugin__InvalidCapacity();

    /*----------  EVENTS ------------------------------------------------*/

    event Plugin__Composed(
        address indexed account,
        uint256 index,
        uint256 velocity
    );
    event Plugin__ClaimedAndDistributed(uint256 bribeAmount, uint256 incentivesAmount, uint256 developerAmount, uint256 treasuryAmount);
    event Plugin__ComposePriceSet(uint256 composePrice);
    event Plugin__CapacitySet(uint256 capacity);
    event Plugin__ActiveBribesSet(bool activeBribes);
    event Plugin__ActiveIncentivesSet(bool activeIncentives);
    event Plugin__TreasurySet(address treasury);
    event Plugin__DeveloperSet(address developer);
    event Plugin__IncentivesSet(address incentives);

    /*----------  MODIFIERS  --------------------------------------------*/

    modifier onlyVoter() {
        if (msg.sender != voter) revert Plugin__NotAuthorizedVoter();
        _;
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    /**
     * @notice Deploy the MapPlugin contract that acts as a Beradrome plugin for BeatConnect.
     * @param _token The main token used for payment (WBERA).
     * @param _voter The Beradrome Voter contract address.
     * @param _assetTokens Typically an array containing [WBERA].
     * @param _bribeTokens Typically an array containing [WBERA].
     * @param _treasury The address of BeatConnect's treasury.
     * @param _vaultFactory The Berachain RewardVault factory that creates a specialized vault for this plugin.
     */
    constructor(
        address _token,
        address _voter,
        address[] memory _assetTokens,
        address[] memory _bribeTokens,
        address _treasury,
        address _developer,
        address _vaultFactory
    ) {
        token = IERC20(_token);
        voter = _voter;
        assetTokens = _assetTokens;
        bribeTokens = _bribeTokens;
        treasury = _treasury;
        developer = _developer;
        incentives = _treasury;

        OTOKEN = IVoter(_voter).OTOKEN();
        vaultToken = address(new VaultToken());
        rewardVault = IBerachainRewardVaultFactory(_vaultFactory).createRewardVault(address(vaultToken));
    }

    /**
     * @notice Distributes accumulated BERA fees from music composition:
     *         - 42% to bribes if activeBribes is true, otherwise to incentives
     *         - 42% to incentives if activeIncentives is true, otherwise to bribes
     *         - 8% to developer
     *         - 8% to treasury
     */
    function claimAndDistribute() external nonReentrant {
        uint256 balance = token.balanceOf(address(this));
        if (balance > DURATION) {
            uint256 bribeAmount = balance * 42 / 100;
            uint256 incentivesAmount = balance * 42 / 100;
            uint256 developerAmount = balance * 8 / 100;
            uint256 treasuryAmount = balance - bribeAmount - incentivesAmount - developerAmount;
            
            token.safeTransfer(developer, developerAmount);
            token.safeTransfer(treasury, treasuryAmount);

            uint256 totalIncentiveAmount = bribeAmount + incentivesAmount;
            if (activeBribes) {
                if (activeIncentives) {
                    token.safeTransfer(incentives, incentivesAmount);
                    token.safeApprove(bribe, 0);
                    token.safeApprove(bribe, bribeAmount);
                    IBribe(bribe).notifyRewardAmount(address(token), bribeAmount);
                    emit Plugin__ClaimedAndDistributed(bribeAmount, incentivesAmount, developerAmount, treasuryAmount);
                } else {
                    token.safeApprove(bribe, 0);
                    token.safeApprove(bribe, totalIncentiveAmount);
                    IBribe(bribe).notifyRewardAmount(address(token), totalIncentiveAmount);
                    emit Plugin__ClaimedAndDistributed(totalIncentiveAmount, 0, developerAmount, treasuryAmount);
                }
            } else {
                token.safeTransfer(incentives, totalIncentiveAmount);
                emit Plugin__ClaimedAndDistributed(0, totalIncentiveAmount, developerAmount, treasuryAmount);
            }
        }
    }

    /**
     * @notice Allows a user (or a proxy) to compose multiple notes in a single transaction.
     *         This can overwrite existing notes, removing the previous owner's stake from the gauge.
     * @param account The address that will effectively own the composed notes.
     * @param indexes An array of note indexes the user wants to claim or overwrite.
     * @param velocities An array of velocities for the notes.
     */
    function composeFor(
        address account,
        uint256[] calldata indexes,
        uint256[] calldata velocities
    ) external nonReentrant {
        if (indexes.length == 0) revert Plugin__InvalidZeroInput();
        if (indexes.length != velocities.length) revert Plugin__InvalidLength();

        for (uint256 i = 0; i < indexes.length; i++) {
            if (indexes[i] >= capacity) revert Plugin__InvalidIndex();

            Slot memory prevSlot = index_Slot[indexes[i]];
            index_Slot[indexes[i]] = Slot(account, velocities[i]);

            if (prevSlot.account != address(0)) {
                IGauge(gauge)._withdraw(prevSlot.account, AMOUNT);
                IRewardVault(rewardVault).delegateWithdraw(prevSlot.account, AMOUNT);
                VaultToken(vaultToken).burn(address(this), AMOUNT);
            }
            emit Plugin__Composed(account, indexes[i], velocities[i]);
        }

        uint256 amount = AMOUNT * indexes.length;
        uint256 cost = composePrice * indexes.length;

        totalComposed += amount;
        account_Composed[account] += amount;

        token.safeTransferFrom(msg.sender, address(this), cost);

        IGauge(gauge)._deposit(account, amount);
        VaultToken(vaultToken).mint(address(this), amount);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, amount);
        IRewardVault(rewardVault).delegateStake(account, amount);
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /**
     * @notice Owner can enable/disable auto-bribe (where fees are sent to the bribe contract instead of the treasury).
     * @param _activeBribes The new boolean setting.
     */
    function setActiveBribes(bool _activeBribes) external onlyOwner {
        activeBribes = _activeBribes;
        emit Plugin__ActiveBribesSet(activeBribes);
    }

    /**
     * @notice Owner can enable/disable active incentives (where fees are sent to the incentives contract instead of the treasury).
     * @param _activeIncentives The new boolean setting.
     */
    function setActiveIncentives(bool _activeIncentives) external onlyOwner {
        activeIncentives = _activeIncentives;
        emit Plugin__ActiveIncentivesSet(activeIncentives);
    }

    /**
     * @notice Owner can set the price (in BERA) required to compose a single note.
     * @param _composePrice The new price per note.
     */
    function setComposePrice(uint256 _composePrice) external onlyOwner {
        composePrice = _composePrice;
        emit Plugin__ComposePriceSet(composePrice);
    }

    /**
     * @notice Owner can expand the capacity of the sequencer, allowing more notes.
     * @param _capacity The new maximum grid capacity.
     */
    function setCapacity(uint256 _capacity) external onlyOwner {
        if (_capacity <= capacity) revert Plugin__InvalidCapacity();
        capacity = _capacity;
        emit Plugin__CapacitySet(capacity);
    }

    /**
     * @notice Owner can update the treasury address.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Plugin__InvalidZeroAddress();
        treasury = _treasury;
        emit Plugin__TreasurySet(treasury);
    }

    /**
     * @notice Owner can update the developer address.
     * @param _developer The new developer address.
     */
    function setDeveloper(address _developer) external {
        if (msg.sender != developer) revert Plugin__NotAuthorizedDeveloper();
        if (_developer == address(0)) revert Plugin__InvalidZeroAddress();
        developer = _developer;
        emit Plugin__DeveloperSet(developer);
    }

    function setIncentives(address _incentives) external onlyOwner {
        if (_incentives == address(0)) revert Plugin__InvalidZeroAddress();
        incentives = _incentives;
        emit Plugin__IncentivesSet(incentives);
    }

    /**
     * @notice Only the voter contract can set the gauge address for oBERO rewards.
     * @param _gauge The new gauge contract address.
     */
    function setGauge(address _gauge) external onlyVoter {
        gauge = _gauge;
    }

    /**
     * @notice Only the voter contract can set the bribe address for distributing hiBERO bribes.
     * @param _bribe The new bribe contract address.
     */
    function setBribe(address _bribe) external onlyVoter {
        bribe = _bribe;
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    /**
     * @notice Returns the staked balance of a specific user in the gauge.
     * @param account The user's address.
     * @return The gauge balance of that user.
     */
    function balanceOf(address account) public view returns (uint256) {
        return IGauge(gauge).balanceOf(account);
    }

    /**
     * @notice Returns the total staked supply in the gauge.
     */
    function totalSupply() public view returns (uint256) {
        return IGauge(gauge).totalSupply();
    }

    /**
     * @return Address of the ERC20 token used to pay for composing music.
     */
    function getToken() public view returns (address) {
        return address(token);
    }

    /**
     * @return The plugin's protocol name (for front-end display).
     */
    function getProtocol() public view virtual returns (string memory) {
        return PROTOCOL;
    }

    /**
     * @return The plugin's name (for front-end display).
     */
    function getName() public view virtual returns (string memory) {
        return NAME;
    }

    /**
     * @return The Beradrome Voter address linked to this plugin.
     */
    function getVoter() public view returns (address) {
        return voter;
    }

    /**
     * @return The gauge address used for staking note positions.
     */
    function getGauge() public view returns (address) {
        return gauge;
    }

    /**
     * @return The bribe contract address.
     */
    function getBribe() public view returns (address) {
        return bribe;
    }

    /**
     * @return A list of asset tokens associated with this plugin (e.g., [WBERA]).
     */
    function getAssetTokens() public view returns (address[] memory) {
        return assetTokens;
    }

    /**
     * @return A list of tokens used for bribing (e.g., [WBERA]).
     */
    function getBribeTokens() public view returns (address[] memory) {
        return bribeTokens;
    }

    /**
     * @return The address of the VaultToken contract used to represent user stakes.
     */
    function getVaultToken() public view returns (address) {
        return vaultToken;
    }

    /**
     * @return The RewardVault address created by the vault factory for PoL integration.
     */
    function getRewardVault() public view returns (address) {
        return rewardVault;
    }

    /**
     * @notice Retrieves details of a single note on the board.
     * @param index Note index in [0..capacity-1].
     * @return account The user who owns the note.
     * @return velocity The velocity of the note.
     */
    function getSlot(uint256 index) public view returns (address account, uint256 velocity) {
        Slot memory slot = index_Slot[index];
        return (slot.account, slot.velocity); 
    }

    /**
     * @notice Retrieves a batch of slots from startIndex to endIndex (inclusive).
     * @param startIndex The first slot index in the range.
     * @param endIndex   The last slot index in the range.
     * @return An array of Slot structs for [startIndex..endIndex].
     */
    function getSlots(uint256 startIndex, uint256 endIndex) public view returns (Slot[] memory) {
        Slot[] memory slots = new Slot[](endIndex - startIndex + 1);
        for (uint256 i = 0; i < slots.length; i++) {
            slots[i] = index_Slot[startIndex + i];
        }
        return slots;
    }
    
}
