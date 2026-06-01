// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderbook} from "./IOrderbook.sol";

/// @dev Minimal ERC20 surface the orderbook needs. The provided `MockERC20`
///      implements all of these methods (plus `mint`).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title Orderbook (template)
/// @notice Skeleton to complete. The constructor, immutable
///         token wiring, and the two trivial getters are already done —
///         everything else reverts with `"NotImplemented"`.
///
///         You are free to add additional state, structs, errors, and
///         helper functions. The only hard constraints are:
///         (1) keep the `IOrderbook` ABI exactly as declared in the
///             interface (the grading harness depends on it), and
///         (2) keep `baseToken`/`quoteToken` as immutables set in the
///             constructor.
contract Orderbook is IOrderbook {
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;

    uint256 private constant WAD = 1e18;

    struct Order {
        uint256 id;
        address maker;
        uint256 price;
        uint256 amount;
    }

    Order[] private bids;
    Order[] private asks;

    uint256 private nextOrderId = 1;

    /// @dev Suggested events. These are a starting point — your
    ///      implementation may emit a different set, rename them, or omit
    ///      events entirely. Nothing in the grading harness depends on
    ///      these signatures.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        Side side,
        uint256 price,
        uint256 amount
    );
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 fillAmount,
        uint256 fillPrice
    );
    event OrderCleared();

    constructor(address _baseToken, address _quoteToken) {
        require(_baseToken != address(0), "baseToken=0");
        require(_quoteToken != address(0), "quoteToken=0");
        require(_baseToken != _quoteToken, "base==quote");
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function getQuoteToken() external view returns (address) {
        return address(quoteToken);
    }

    function placeLimitOrder(Side side, uint256 price, uint256 amount) external returns (uint256) {
        require(price > 0, "price=0");
        require(amount > 0, "amount=0");

        uint256 orderId = nextOrderId++;

        if (side == Side.BUY) {
            uint256 quoteLocked = quoteFor(amount, price);
            require(quoteToken.transferFrom(msg.sender, address(this), quoteLocked), "quote transfer failed");
            bids.push(Order({id: orderId, maker: msg.sender, price: price, amount: amount}));
        } else {
            require(baseToken.transferFrom(msg.sender, address(this), amount), "base transfer failed");
            asks.push(Order({id: orderId, maker: msg.sender, price: price, amount: amount}));
        }

        emit OrderPlaced(orderId, msg.sender, side, price, amount);
        return orderId;
    }

    function placeMarketOrder(Side side, uint256 amount) external {
        require(amount > 0, "amount=0");
        uint256 remaining = amount;

        if (side == Side.BUY) {
            while (remaining > 0 && asks.length > 0) {
                uint256 idx = bestAskIndex();
                Order storage ask = asks[idx];

                uint256 fill = remaining < ask.amount ? remaining : ask.amount;
                uint256 quoteAmt = quoteFor(fill, ask.price);

                require(quoteToken.transferFrom(msg.sender, ask.maker, quoteAmt), "quote transfer failed");
                require(baseToken.transfer(msg.sender, fill), "base transfer failed");

                emit OrderFilled(ask.id, msg.sender, fill, ask.price);

                remaining -= fill;
                ask.amount -= fill;
                if (ask.amount == 0) removeAt(asks, idx);
            }
        } else {
            while (remaining > 0 && bids.length > 0) {
                uint256 idx = bestBidIndex();
                Order storage bid = bids[idx];

                uint256 fill = remaining < bid.amount ? remaining : bid.amount;
                uint256 quoteAmt = quoteFor(fill, bid.price);

                require(baseToken.transferFrom(msg.sender, bid.maker, fill), "base transfer failed");
                require(quoteToken.transfer(msg.sender, quoteAmt), "quote transfer failed");

                emit OrderFilled(bid.id, msg.sender, fill, bid.price);

                remaining -= fill;
                bid.amount -= fill;
                if (bid.amount == 0) removeAt(bids, idx);
            }
        }
    }

    function clear() external {
        for (uint256 i = 0; i < bids.length; i++) {
            Order storage bid = bids[i];
            require(quoteToken.transfer(bid.maker, quoteFor(bid.amount, bid.price)), "quote refund failed");
        }
        for (uint256 i = 0; i < asks.length; i++) {
            Order storage ask = asks[i];
            require(baseToken.transfer(ask.maker, ask.amount), "base refund failed");
        }
        delete bids;
        delete asks;
        emit OrderCleared();
    }

    function getBidsCount() external view returns (uint256) {
        return bids.length;
    }

    function getAsksCount() external view returns (uint256) {
        return asks.length;
    }

    function getMidPrice() external view returns (uint256) {
        require(bids.length > 0 && asks.length > 0, "empty side");
        uint256 bestBid = bids[bestBidIndex()].price;
        uint256 bestAsk = asks[bestAskIndex()].price;
        return (bestBid + bestAsk) / 2;
    }

    function quoteFor(uint256 amount, uint256 price) private pure returns (uint256) {
        return (amount * price) / WAD;
    }

    function bestBidIndex() private view returns (uint256 best) {
        uint256 bestPrice = bids[0].price;
        for (uint256 i = 1; i < bids.length; i++) {
            if (bids[i].price > bestPrice) {
                bestPrice = bids[i].price;
                best = i;
            }
        }
    }

    function bestAskIndex() private view returns (uint256 best) {
        uint256 bestPrice = asks[0].price;
        for (uint256 i = 1; i < asks.length; i++) {
            if (asks[i].price < bestPrice) {
                bestPrice = asks[i].price;
                best = i;
            }
        }
    }

    function removeAt(Order[] storage arr, uint256 idx) private {
        uint256 last = arr.length - 1;
        if (idx != last) {
            arr[idx] = arr[last];
        }
        arr.pop();
    }
}
