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

#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

namespace {
#ifdef _WIN32
const std::string tokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string tokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

const std::string questionSchema = R"({"type":"object","properties":{"questions":{"type":"array"}}})";

class Gemma4BareRecoveryContractTest : public ::testing::Test {
protected:
    static std::unique_ptr<ov::genai::Tokenizer> tokenizer;

    static void SetUpTestSuite() {
        const char* configured = std::getenv("GEMMA4_TOKENIZER_PATH");
        tokenizer = std::make_unique<ov::genai::Tokenizer>(configured ? configured : tokenizerPath);
    }

    static void TearDownTestSuite() {
        tokenizer.reset();
    }

    static ToolsSchemas_t questionTools() {
        ToolsSchemas_t tools;
        tools.emplace("question", ToolSchemaWrapper{nullptr, questionSchema});
        return tools;
    }
};

std::unique_ptr<ov::genai::Tokenizer> Gemma4BareRecoveryContractTest::tokenizer;
}  // namespace

TEST_F(Gemma4BareRecoveryContractTest, AllowedToolNameFollowedByProseStaysContent) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", questionTools());

    auto delta = parser.parseChunk(
        "call:question prose", {}, true, ov::genai::GenerationFinishReason::STOP);

    ASSERT_TRUE(delta.has_value());
    ASSERT_TRUE(std::holds_alternative<ContentDelta>(*delta));
    EXPECT_EQ(std::get<ContentDelta>(*delta).text, "call:question prose");
}

TEST_F(Gemma4BareRecoveryContractTest, BareCallRecoverySurvivesToolNameChunkSplit) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", questionTools());

    auto first = parser.parseChunk(
        "call:quest", {}, true, ov::genai::GenerationFinishReason::NONE);
    EXPECT_FALSE(first.has_value());

    auto second = parser.parseChunk(
        "ion{questions:[]}<tool_call|>", {}, true, ov::genai::GenerationFinishReason::NONE);
    EXPECT_FALSE(second.has_value());

    std::optional<Delta> toolDelta;
    for (int drain = 0; drain < 4 && !toolDelta.has_value(); ++drain) {
        auto delta = parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::NONE);
        if (delta.has_value() && std::holds_alternative<ToolCallDelta>(*delta)) {
            toolDelta = std::move(delta);
        }
    }

    ASSERT_TRUE(toolDelta.has_value());
    const auto& call = std::get<ToolCallDelta>(*toolDelta);
    EXPECT_EQ(call.index, 0);
    EXPECT_EQ(call.name.value_or(""), "question");
    EXPECT_EQ(call.arguments, R"({"questions":[]})");
}
