//*****************************************************************************
// Copyright 2025 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//*****************************************************************************

#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <unordered_map>

#include "../http_frontend/multi_part_parser_drogon_impl.hpp"

TEST(DrogonHttpHeaderCopy, SessionHeadersSurviveReqHeadersCopyUsedByV3Dispatcher) {
    auto req = drogon::HttpRequest::newHttpRequest();
    req->addHeader("X-OVMS-Session-ID", "gemma4-live-test");
    req->addHeader("X-OVMS-Session-Store", "C:\\tmp\\gemma4-session-store");
    req->addHeader("Content-Type", "application/json");

    std::unordered_map<std::string, std::string> headers;
    for (const auto& header : req->headers()) {
        headers[header.first] = header.second;
    }

    auto asciiLower = [](std::string value) {
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        return value;
    };

    std::unordered_map<std::string, std::string> lowered;
    for (const auto& [name, value] : headers) {
        lowered.emplace(asciiLower(name), value);
    }
    ASSERT_EQ(lowered["x-ovms-session-id"], "gemma4-live-test") << "inbound session headers never reached req->headers()";
    ASSERT_EQ(lowered["x-ovms-session-store"], "C:\\tmp\\gemma4-session-store");
    ASSERT_NE(lowered["content-type"].find("application/json"), std::string::npos);
}

// Sanity test, drogon already unit tests it in depth
TEST(MultiPartParserDrogonImpl, GetFieldName) {
    auto req = drogon::HttpRequest::newHttpRequest();
    req->setMethod(drogon::Post);
    req->addHeader("content-type", "multipart/form-data; boundary=\"12345\"");
    req->setBody(
        "--12345\r\n"
        "Content-Disposition: form-data; name=\"somekey\"\r\n"
        "\r\n"
        "Hello; World\r\n"
        "--12345--");

    ovms::DrogonMultiPartParser parser(req);
    ASSERT_TRUE(parser.parse());
    ASSERT_FALSE(parser.hasParseError());
    std::string val = std::string(parser.getFieldByName("somekey"));
    EXPECT_EQ(val, "Hello; World");
}
TEST(MultiPartParserDrogonImpl, GetArrayFieldName) {
    auto req = drogon::HttpRequest::newHttpRequest();
    req->setMethod(drogon::Post);
    req->addHeader("content-type", "multipart/form-data; boundary=\"12345\"");
    req->setBody(
        "--12345\r\n"
        "Content-Disposition: form-data; name=\"arraykey[]\"\r\n"
        "\r\n"
        "value1\r\n"
        "--12345\r\n"
        "Content-Disposition: form-data; name=\"arraykey[]\"\r\n"
        "\r\n"
        "value2\r\n"
        "--12345\r\n"
        "Content-Disposition: form-data; name=\"arraykey[]\"\r\n"
        "\r\n"
        "value3\r\n"
        "--12345--");

    ovms::DrogonMultiPartParser parser(req);
    ASSERT_TRUE(parser.parse());
    ASSERT_FALSE(parser.hasParseError());
    auto values = parser.getArrayFieldByName("arraykey[]");
    ASSERT_EQ(values.size(), 3);
    EXPECT_EQ(values[0], "value1");
    EXPECT_EQ(values[1], "value2");
    EXPECT_EQ(values[2], "value3");
}
TEST(MultiPartParserDrogonImpl, GetFileContentByName) {
    auto req = drogon::HttpRequest::newHttpRequest();
    req->setMethod(drogon::Post);
    req->addHeader("content-type", "multipart/form-data; boundary=\"12345\"");
    req->setBody(
        "--12345\r\n"
        "Content-Disposition: form-data; name=\"somekey\"; "
        "filename=\"test\"\r\n"
        "\r\n"
        "Hello; World\r\n"
        "--12345--");

    ovms::DrogonMultiPartParser parser(req);
    ASSERT_TRUE(parser.parse());
    ASSERT_FALSE(parser.hasParseError());
    std::string val = std::string(parser.getFileContentByFieldName("somekey"));
    EXPECT_EQ(val, "Hello; World");
}
