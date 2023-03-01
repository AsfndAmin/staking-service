// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./base/BasePool.sol";
import "./interfaces/ITimeLockPool.sol";

contract TimeLockPool is BasePool, ITimeLockPool {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public immutable maxLockDuration = 5 minutes;
    uint256 public constant MIN_LOCK_DURATION = 1 minutes;

    bytes32 public constant REWARD_DISTRIBUTOR_ROLE =
        keccak256("REWARD_DISTRIBUTOR_ROLE");

    mapping(address => Deposit[]) public depositsOf;

    struct Deposit {
        uint256 amount;
        uint64 start;
        uint64 end;
    }

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken
    ) BasePool(_owner, _name, _symbol, _depositToken, _rewardToken) {}

    event Deposited(
        uint256 amount,
        uint256 duration,
        address indexed receiver,
        address indexed from
    );
    event Withdrawn(
        uint256 indexed depositId,
        address indexed receiver,
        address indexed from,
        uint256 amount
    );

    modifier onlyRewardDistributor() {
        require(
            hasRole(REWARD_DISTRIBUTOR_ROLE, _msgSender()),
            "LiquidityMiningManager.onlyRewardDistributor: permission denied"
        );
        _;
    }

    function deposit(uint256 _amount, address _receiver) external override {
        require(_amount > 0, "TimeLockPool.deposit: cannot deposit 0");
        depositToken.safeTransferFrom(_msgSender(), address(this), _amount);

        depositsOf[_receiver].push(
            Deposit({
                amount: _amount,
                start: uint64(block.timestamp),
                end: uint64(block.timestamp) + uint64(maxLockDuration)
            })
        );

        _mint(_receiver, _amount);
        emit Deposited(_amount, maxLockDuration, _receiver, _msgSender());
    }

    function withdraw(uint256 _depositId, address _receiver) external {
        require(
            _depositId < depositsOf[_msgSender()].length,
            "TimeLockPool.withdraw: Deposit does not exist"
        );
        Deposit memory userDeposit = depositsOf[_msgSender()][_depositId];
        require(
            block.timestamp >= userDeposit.end,
            "TimeLockPool.withdraw: too soon"
        );

        uint256 shareAmount = userDeposit.amount;

        // remove Deposit
        depositsOf[_msgSender()][_depositId] = depositsOf[_msgSender()][
            depositsOf[_msgSender()].length - 1
        ];
        depositsOf[_msgSender()].pop();

        // burn pool shares
        _burn(_msgSender(), shareAmount);

        // return tokens
        depositToken.safeTransfer(_receiver, userDeposit.amount);
        emit Withdrawn(_depositId, _receiver, _msgSender(), userDeposit.amount);
    }

    function distributeRewards(uint256 _amount)
        public
        override
        onlyRewardDistributor
    {
        rewardToken.safeTransferFrom(_msgSender(), address(this), _amount);
        _distributeRewards(_amount);
    }

    function getTotalDeposit(address _account) public view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < depositsOf[_account].length; i++) {
            total += depositsOf[_account][i].amount;
        }

        return total;
    }

    function getDepositsOf(address _account)
        public
        view
        returns (Deposit[] memory)
    {
        return depositsOf[_account];
    }

    function getDepositsOfLength(address _account)
        public
        view
        returns (uint256)
    {
        return depositsOf[_account].length;
    }
}
