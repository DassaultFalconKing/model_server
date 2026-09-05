//*****************************************************************************
// Copyright 2026 Intel Corporation
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

#include <gtest/gtest.h>
#include <openvino/genai/tokenizer.hpp>
#include <memory>
#include <optional>
#include <string>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

namespace {
#ifdef _WIN32
const std::string tokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string tokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

std::string serialize(const std::optional<rapidjson::Document>& doc) {
    if (!doc.has_value())
        return {};
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    doc->Accept(writer);
    return buffer.GetString();
}
}  // namespace

TEST(Gemma4StreamingHardeningTest, SplitToolCallStartTagDoesNotLeakIntoContent) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    const ToolsSchemas_t emptyToolsSchema{};
    OutputParser parser(tokenizer, "gemma4", "gemma4", emptyToolsSchema);

    auto contentDelta = parser.parseChunk("before", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(contentDelta.has_value());
    EXPECT_EQ(serialize(contentDelta), R"({"delta":{"content":"before"}})");

    // A proxy/harness may split decoded special-token text at arbitrary byte
    // boundaries. A partial opener must be retained until it can be classified.
    EXPECT_FALSE(parser.parseChunk("<|tool_", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    EXPECT_FALSE(parser.parseChunk("call>call:ls", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());

    auto firstDelta = parser.parseChunk("{a:", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(firstDelta.has_value());
    EXPECT_NE(serialize(firstDelta).find("\"name\":\"ls\""), std::string::npos);

    auto argsDelta = parser.parseChunk("true}", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(argsDelta.has_value());
    EXPECT_NE(serialize(argsDelta).find("{\\\"a\\\":true}"), std::string::npos);
}

TEST(Gemma4StreamingHardeningTest, SplitToolCallEndTagDoesNotLeakIntoContent) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    const ToolsSchemas_t emptyToolsSchema{};
    OutputParser parser(tokenizer, "gemma4", "gemma4", emptyToolsSchema);

    EXPECT_FALSE(parser.parseChunk("<|tool_call>", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    EXPECT_FALSE(parser.parseChunk("call:ls", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());

    auto firstDelta = parser.parseChunk("{a:", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(firstDelta.has_value());
    EXPECT_NE(serialize(firstDelta).find("\"name\":\"ls\""), std::string::npos);

    auto argsDelta = parser.parseChunk("true}", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(argsDelta.has_value());
    EXPECT_NE(serialize(argsDelta).find("{\\\"a\\\":true}"), std::string::npos);

    EXPECT_FALSE(parser.parseChunk("<tool_", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    EXPECT_FALSE(parser.parseChunk("call|>", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());

    auto contentDelta = parser.parseChunk("after", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(contentDelta.has_value());
    EXPECT_EQ(serialize(contentDelta), R"({"delta":{"content":"after"}})");
}
