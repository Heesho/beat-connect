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
 *         Whenever a user places pixels, an equivalent amount of VaultToken is minted and
 *         staked into the RewardVault. When pixels are overwritten, these tokens are burned.
 */
contract VaultToken is ERC20, Ownable {
    /**
     * @notice Initializes the ERC20 with a name ("BentoBera") and symbol ("BentoBera").
     */
    constructor() ERC20("BentoBera", "BentoBera") {}

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
 * @notice This contract represents the BentoBera onchain pixel grid as a Beradrome plugin.
 *         - Players place or overwrite pixels by paying BERA (token).
 *         - Staking logic is handled via a Gauge and a specialized RewardVault.
 *         - Factions can be created, and each pixel is assigned to exactly one faction.
 *         - The contract distributes fees for bribes, treasury, and faction ownership.
 */
contract MapPlugin is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    /**
     * @dev DURATION is used as a threshold for deciding when to perform claim/distribute operations.
     */
    uint256 public constant DURATION = 7 days;
    /**
     * @dev Each pixel placed in the grid increments the staked amount by 1 (AMOUNT = 1).
     *      This can be seen as a “unit stake” for each pixel.
     */
    uint256 public constant AMOUNT = 1;

    /**
     * @notice Display strings to identify the plugin’s protocol and name.
     */
    string public constant PROTOCOL = "Future Girls Inc";
    string public constant NAME = "BentoBera";  

    /*----------  STATE VARIABLES  --------------------------------------*/

    /**
     * @notice The ERC20 token used to pay for placing pixels (likely WBERA).
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
     * @notice The gauge contract address where staked amounts (pixels) earn oBERO rewards.
     */
    address private gauge;
    /**
     * @notice The bribe contract address for distributing bribes to hiBERO voters.
     */
    address private bribe;

    /**
     * @notice The VaultToken contract used to represent staked positions (minted/burned on pixel place/overwrite).
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
     * @notice The maximum index allowed for placing pixels (initially 100, can be extended).
     *         If `capacity = 100`, valid pixel indexes are from 0 to 99, for instance.
     */
    uint256 public capacity = 100;
    /**
     * @notice The cost to place or overwrite a single pixel in BERA terms.
     */
    uint256 public placePrice = 0.01 ether;
    /**
     * @notice The highest assigned faction index, incremented each time a new faction is created.
     */
    uint256 public factionMax;
    /**
     * @notice The total number of pixel placements on the board. 
     *         Summation of all placed pixels across all addresses/factions.
     */
    uint256 public totalPlaced;
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
     * @notice Represents a single pixel on the grid.
     * @param account The user who currently owns/placed this pixel.
     * @param faction The faction ID that the pixel belongs to.
     * @param color   A string representing the pixel color in #RRGGBB format.
     */
    struct Pixel {
        address account;
        uint256 faction;
        string color;
    }

    /**
     * @notice Represents a faction that can hold pixels.
     * @param owner   The address controlling this faction (e.g., a guild leader).
     * @param balance The total staked pixels controlled by this faction (for reward calculations).
     * @param placed  The lifetime total of placed pixels associated with this faction.
     * @param isActive Whether the faction is active or not.
     */
    struct Faction {
        address owner;
        uint256 balance;
        uint256 placed;
        bool isActive;
    }

    /**
     * @notice index => Pixel data. 
     *         Where index is the pixel ID (0..capacity-1).
     */
    mapping(uint256 => Pixel) public index_Pixel;

    /**
     * @notice faction ID => Faction struct
     */
    mapping(uint256 => Faction) public index_Faction;
    /**
     * @notice Maps a faction owner’s address to their faction ID. 
     *         Useful to quickly find which faction they control.
     */
    mapping(address => uint256) public factionOwner_Index;

    /**
     * @notice Maps each address to the total number of pixels they have placed on the board.
     */
    mapping(address => uint256) public account_Placed;

    /**
     * @notice Tracks how many pixels each user has contributed to a particular faction’s balance.
     */
    mapping(address => mapping(uint256 => uint256)) public account_Faction_Balance;
    /**
     * @notice Tracks how many pixels each user has placed historically for a particular faction.
     */
    mapping(address => mapping(uint256 => uint256)) public account_Faction_Placed;

    /*----------  ERRORS ------------------------------------------------*/

    error Plugin__InvalidFaction();
    error Plugin__FactionInactive();
    error Plugin__InvalidColor();
    error Plugin__InvalidIndex();
    error Plugin__InvalidZeroInput();
    error Plugin__NotAuthorizedVoter();
    error Plugin__InvalidCapacity();
    error Plugin__InvalidZeroAddress();
    error Plugin__NotAuthorizedDeveloper();

    /*----------  EVENTS ------------------------------------------------*/

    event Plugin__Placed(
        address indexed account,
        uint256 faction,
        uint256 index,
        string color
    );
    event Plugin__ClaimedAndDistributed(uint256 bribeAmount, uint256 incentivesAmount, uint256 developerAmount, uint256 treasuryAmount);
    event Plugin__PlacePriceSet(uint256 placePrice);
    event Plugin__CapacitySet(uint256 capacity);
    event Plugin__FactionCreated(uint256 faction);
    event Plugin__FactionActiveSet(uint256 faction, bool isActive);
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
     * @notice Deploy the MapPlugin contract that acts as a Beradrome plugin for BentoBera.
     * @param _token The main token used for payment (WBERA).
     * @param _voter The Beradrome Voter contract address.
     * @param _assetTokens Typically an array containing [WBERA].
     * @param _bribeTokens Typically an array containing [WBERA].
     * @param _treasury The address of BentoBera's treasury.
     * @param _vaultFactory The Berachain RewardVault factory that creates a specialized vault for this plugin.
     */
    constructor(
        address _token, // WBERA
        address _voter,
        address[] memory _assetTokens, // [WBERA]
        address[] memory _bribeTokens, // [WBERA]
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
     * @notice Distributes accumulated BERA fees (95% of total placement fees):
     *         - 42% to bribes if activeBribes is true, otherwise to incentives
     *         - 42% to incentives if activeIncentives is true, otherwise to bribes
     *         - 8% to developer
     *         - 8% to treasury (remaining balance)
     * @dev Final distribution of total fees:
     *      - 5% to faction owner (taken during placement)
     *      - 39.9% to bribes
     *      - 39.9% to incentives
     *      - 7.6% to developer
     *      - 7.6% to treasury
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
     * @notice Allows a user (or a proxy) to place multiple pixels for a given faction in a single transaction.
     *         This can overwrite existing pixels, removing the previous owner’s stake from the gauge.
     * @param account The address that will effectively own the placed pixels.
     * @param faction The faction ID under which these pixels are placed.
     * @param color   The color in #RRGGBB format for the pixels.
     * @param indexes An array of pixel indexes the user wants to claim or overwrite.
     */
    function placeFor(
        address account,
        uint256 faction,
        string calldata color,
        uint256[] calldata indexes
    ) external nonReentrant {
        if (faction == 0 || faction > factionMax) revert Plugin__InvalidFaction();
        if (!index_Faction[faction].isActive) revert Plugin__FactionInactive();
        if (indexes.length == 0) revert Plugin__InvalidZeroInput();
        if (!validateColorFormat(color)) revert Plugin__InvalidColor();

        for (uint256 i = 0; i < indexes.length; i++) {
            if (indexes[i] >= capacity) revert Plugin__InvalidIndex();

            Pixel memory prevPixel = index_Pixel[indexes[i]];
            index_Pixel[indexes[i]] = Pixel(account, faction, color);

            if (prevPixel.account != address(0)) {

                index_Faction[prevPixel.faction].balance -= AMOUNT;
                account_Faction_Balance[prevPixel.account][prevPixel.faction] -= AMOUNT;

                IGauge(gauge)._withdraw(prevPixel.account, AMOUNT);
                IRewardVault(rewardVault).delegateWithdraw(prevPixel.account, AMOUNT);
                VaultToken(vaultToken).burn(address(this), AMOUNT);
            }
            emit Plugin__Placed(account, faction, indexes[i], color);
        }

        uint256 amount = AMOUNT * indexes.length;
        uint256 cost = placePrice * indexes.length;
        uint256 fee = cost / 20;

        totalPlaced += amount;
        account_Placed[account] += amount;
        index_Faction[faction].balance += amount;
        account_Faction_Balance[account][faction] += amount;
        index_Faction[faction].placed += amount;
        account_Faction_Placed[account][faction] += amount;

        token.safeTransferFrom(msg.sender, index_Faction[faction].owner, fee);
        token.safeTransferFrom(msg.sender, address(this), cost - fee);

        IGauge(gauge)._deposit(account, amount);
        VaultToken(vaultToken).mint(address(this), amount);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, amount);
        IRewardVault(rewardVault).delegateStake(account, amount);
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /**
     * @notice Owner can create a new faction, assigning an owner address.
     * @param _owner The address controlling the new faction.
     */
    function createFaction(address _owner) external onlyOwner {
        factionMax++;
        index_Faction[factionMax] = Faction(_owner, 0, 0, true);
        factionOwner_Index[_owner] = factionMax;
        emit Plugin__FactionCreated(factionMax);
    }

    /**
     * @notice Owner can toggle the active status of a faction (preventing new pixels from being placed under it if inactive).
     * @param _faction The faction ID.
     * @param _isActive True to activate, false to deactivate.
     */
    function setFactionActive(uint256 _faction, bool _isActive) external onlyOwner {
        index_Faction[_faction].isActive = _isActive;
        emit Plugin__FactionActiveSet(_faction, _isActive);
    }

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
     * @notice Owner can set the price (in BERA) required to place a single pixel.
     * @param _placePrice The new price per pixel.
     */
    function setPlacePrice(uint256 _placePrice) external onlyOwner {
        placePrice = _placePrice;
        emit Plugin__PlacePriceSet(placePrice);
    }

    /**
     * @notice Owner can expand the capacity of the grid, allowing higher pixel indices.
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

    /**
     * @dev Validates that a string is in the "#RRGGBB" hex format.
     *      Used to prevent spamming arbitrary data as color.
     * @param color The color string.
     * @return True if valid format, false otherwise.
     */
    function validateColorFormat(string memory color) internal pure returns (bool) {
        bytes memory colorBytes = bytes(color);
        if (colorBytes.length != 7) return false; // "#RRGGBB" format
        if (colorBytes[0] != '#') return false;
        
        for (uint i = 1; i < 7; i++) {
            bytes1 char = colorBytes[i];
            bool isHexDigit = (
                (char >= '0' && char <= '9') ||
                (char >= 'a' && char <= 'f') ||
                (char >= 'A' && char <= 'F')
            );
            if (!isHexDigit) return false;
        }
        return true;
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    /**
     * @notice Returns the staked balance of a specific user in the gauge.
     * @param account The user’s address.
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
     * @return Address of the ERC20 token used to pay for pixel placements.
     */
    function getToken() public view returns (address) {
        return address(token);
    }

    /**
     * @return The plugin’s protocol name (for front-end display).
     */
    function getProtocol() public view virtual returns (string memory) {
        return PROTOCOL;
    }

    /**
     * @return The plugin’s name (for front-end display).
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
     * @return The gauge address used for staking pixel amounts.
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
     * @notice Retrieves a faction’s details.
     * @param _faction The faction ID.
     * @return owner    The faction owner’s address.
     * @return balance  Current stake count (active pixels) for this faction.
     * @return placed   Total lifetime pixel count assigned to this faction.
     * @return isActive Whether the faction is open for new pixel placements.
     */
    function getFaction(uint256 _faction) public view returns (address owner, uint256 balance, uint256 placed, bool isActive) {
        return (index_Faction[_faction].owner, index_Faction[_faction].balance, index_Faction[_faction].placed, index_Faction[_faction].isActive);
    }

    /**
     * @notice Retrieves details of a single pixel on the board.
     * @param index Pixel index in [0..capacity-1].
     * @return account The user who owns the pixel.
     * @return faction The faction ID of the pixel.
     * @return color   The color string in #RRGGBB format.
     */
    function getPixel(uint256 index) public view returns (address account, uint256 faction, string memory color) {
        Pixel memory pixel = index_Pixel[index];
        return (pixel.account, pixel.faction, pixel.color); 
    }

    /**
     * @notice Retrieves a batch of pixels from startIndex to endIndex (inclusive).
     * @param startIndex The first pixel index in the range.
     * @param endIndex   The last pixel index in the range.
     * @return An array of Pixel structs for [startIndex..endIndex].
     */
    function getPixels(uint256 startIndex, uint256 endIndex) public view returns (Pixel[] memory) {
        Pixel[] memory pixels = new Pixel[](endIndex - startIndex + 1);
        for (uint256 i = 0; i < pixels.length; i++) {
            pixels[i] = index_Pixel[startIndex + i];
        }
        return pixels;
    }
    
}
