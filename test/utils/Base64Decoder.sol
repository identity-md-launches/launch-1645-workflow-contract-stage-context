// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

/// @notice Minimal standard-alphabet Base64 decoder for tests. Reverts on an invalid character.
library Base64Decoder {
    function decode(string memory input) internal pure returns (bytes memory out) {
        bytes memory data = bytes(input);
        uint256 len = data.length;
        if (len == 0) return out;
        require(len % 4 == 0, "base64: bad length");

        uint256 padding;
        if (data[len - 1] == "=") padding++;
        if (data[len - 2] == "=") padding++;

        uint256 outLen = (len / 4) * 3 - padding;
        out = new bytes(outLen);

        uint256 o;
        for (uint256 i; i < len; i += 4) {
            uint256 chunk = (_value(data[i]) << 18) | (_value(data[i + 1]) << 12) | (_value(data[i + 2]) << 6)
                | _value(data[i + 3]);
            if (o < outLen) out[o++] = bytes1(uint8(chunk >> 16));
            if (o < outLen) out[o++] = bytes1(uint8(chunk >> 8));
            if (o < outLen) out[o++] = bytes1(uint8(chunk));
        }
    }

    function _value(bytes1 c) private pure returns (uint256) {
        uint8 b = uint8(c);
        if (b >= 65 && b <= 90) return b - 65; // A-Z
        if (b >= 97 && b <= 122) return b - 97 + 26; // a-z
        if (b >= 48 && b <= 57) return b - 48 + 52; // 0-9
        if (c == "+") return 62;
        if (c == "/") return 63;
        if (c == "=") return 0;
        revert("base64: bad char");
    }

    /// @notice Strips a `prefix` from `s`, reverting when `s` does not start with it.
    function stripPrefix(string memory s, string memory prefix) internal pure returns (string memory) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        require(sb.length >= pb.length, "prefix: too short");
        for (uint256 i; i < pb.length; ++i) {
            require(sb[i] == pb[i], "prefix: mismatch");
        }
        bytes memory rest = new bytes(sb.length - pb.length);
        for (uint256 i; i < rest.length; ++i) {
            rest[i] = sb[pb.length + i];
        }
        return string(rest);
    }
}
