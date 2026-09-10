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
#include <utility>
#include <variant>
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../../llm/io_processing/gemma4/gemma4_tool_parser.hpp"
#include "../../../llm/ovms_text_streamer.hpp"
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

    ParsedOutput parseWithSpecialTokensSkipped(const std::string& input) {
        auto parser = std::make_shared<OutputParser>(*tokenizer, "gemma4", "gemma4", questionTools());
        ParsedOutput result;
        std::vector<ToolCall> toolCalls;

        auto callback = [&](Delta delta, bool /*isLast*/) {
            if (const auto* content = std::get_if<ContentDelta>(&delta)) {
                result.content.append(content->text);
            } else if (const auto* reasoning = std::get_if<ReasoningDelta>(&delta)) {
                result.reasoning.append(reasoning->text);
            } else if (const auto* call = std::get_if<ToolCallDelta>(&delta)) {
                if (call->index >= 0) {
                    const auto index = static_cast<size_t>(call->index);
                    if (index >= toolCalls.size())
                        toolCalls.resize(index + 1);
                    auto& accumulated = toolCalls[index];
                    if (call->id)
                        accumulated.id = *call->id;
                    if (call->name)
                        accumulated.name = *call->name;
                    accumulated.arguments.append(call->arguments);
                }
            }
            return ov::genai::StreamingStatus::RUNNING;
        };

        const ov::AnyMap decodeParams{{ov::genai::skip_special_tokens.name(), true}};
        OVMSTextStreamer streamer(*tokenizer, parser, true, std::move(callback), decodeParams);
        auto tensor = tokenizer->encode(input, ov::genai::add_special_tokens(false)).input_ids;
        for (size_t i = 0; i < tensor.get_size(); ++i)
            streamer.write(tensor.data<int64_t>()[i]);
        streamer.end();

        result.toolCalls = std::move(toolCalls);
        return result;
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

TEST_F(Gemma4BareRecoveryContractTest, LiteralCanonicalToolMarkerInProseStaysContent) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", questionTools());
    const std::string input = "Documentation marker <|tool_call> is literal, not a call.";

    auto delta = parser.parseChunk(
        input, {}, true, ov::genai::GenerationFinishReason::STOP);

    ASSERT_TRUE(delta.has_value());
    ASSERT_TRUE(std::holds_alternative<ContentDelta>(*delta));
    EXPECT_EQ(std::get<ContentDelta>(*delta).text, input);
}

TEST_F(Gemma4BareRecoveryContractTest, RegistryAwareParserReleasesImpossibleBarePrefixAsContent) {
    Gemma4ToolParser parser(*tokenizer, questionTools());

    auto delta = parser.parseChunk(
        "call:question prose", {}, ov::genai::GenerationFinishReason::STOP);

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

TEST_F(Gemma4BareRecoveryContractTest, SkipSpecialTokensStillPreservesCanonicalReasoningToToolHandoff) {
    const auto parsed = parseWithSpecialTokensSkipped(
        "<|channel>thought\nNeed user input<channel|>"
        "<|tool_call>call:question{questions:[]}<tool_call|>");

    EXPECT_EQ(parsed.reasoning, "Need user input");
    EXPECT_TRUE(parsed.content.empty());
    ASSERT_EQ(parsed.toolCalls.size(), 1u);
    EXPECT_EQ(parsed.toolCalls[0].name, "question");
    EXPECT_EQ(parsed.toolCalls[0].arguments, R"({"questions":[]})");
}
