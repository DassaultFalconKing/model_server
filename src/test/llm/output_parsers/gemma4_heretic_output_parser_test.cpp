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
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

namespace {

#ifdef _WIN32
const std::string hereticTokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string hereticTokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

std::unique_ptr<ov::genai::Tokenizer> hereticTokenizer;
const ToolsSchemas_t EMPTY_HERETIC_TOOLS_SCHEMA = {};

struct CollectedDeltas {
    std::vector<std::string> names;
    std::vector<std::string> arguments;
    std::vector<std::string> content;
};

void collectDelta(const std::optional<rapidjson::Document>& doc, CollectedDeltas& collected) {
    if (!doc.has_value() || !doc->IsObject() || !doc->HasMember("delta")) {
        return;
    }
    const auto& delta = (*doc)["delta"];
    if (!delta.IsObject()) {
        return;
    }

    if (delta.HasMember("content") && delta["content"].IsString()) {
        collected.content.emplace_back(delta["content"].GetString());
    }

    if (!delta.HasMember("tool_calls") || !delta["tool_calls"].IsArray()) {
        return;
    }

    for (const auto& toolCall : delta["tool_calls"].GetArray()) {
        if (!toolCall.IsObject() || !toolCall.HasMember("function") || !toolCall["function"].IsObject()) {
            continue;
        }
        const auto& function = toolCall["function"];
        if (function.HasMember("name") && function["name"].IsString()) {
            collected.names.emplace_back(function["name"].GetString());
        }
        if (function.HasMember("arguments") && function["arguments"].IsString()) {
            collected.arguments.emplace_back(function["arguments"].GetString());
        }
    }
}

class Gemma4HereticOutputParserTest : public ::testing::Test {
protected:
    std::unique_ptr<OutputParser> parser;

    static void SetUpTestSuite() {
        try {
            hereticTokenizer = std::make_unique<ov::genai::Tokenizer>(hereticTokenizerPath);
        } catch (const std::exception& e) {
            FAIL() << "Failed to initialize Gemma4 tokenizer: " << e.what();
        }
    }

    static void TearDownTestSuite() {
        hereticTokenizer.reset();
    }

    void SetUp() override {
        // Isolate the tool parser. Reasoning parser behavior has its own test suite.
        parser = std::make_unique<OutputParser>(*hereticTokenizer, "gemma4", "", EMPTY_HERETIC_TOOLS_SCHEMA);
    }

    void feed(CollectedDeltas& collected, const std::string& chunk, ov::genai::GenerationFinishReason finishReason) {
        collectDelta(parser->parseChunk(chunk, {}, true, finishReason), collected);
    }
};

TEST_F(Gemma4HereticOutputParserTest, CompleteToolCallDeliveredInOneStreamingChunkIsFullyDrained) {
    CollectedDeltas collected;

    feed(collected,
        "<|tool_call>call:get_weather{city:<|\"|>Berlin<|\"|>,days:2}<tool_call|>",
        ov::genai::GenerationFinishReason::NONE);
    // A backend is allowed to deliver no further text and only signal the finish event.
    feed(collected, "", ov::genai::GenerationFinishReason::STOP);

    ASSERT_EQ(collected.names.size(), 1);
    EXPECT_EQ(collected.names[0], "get_weather");
    ASSERT_EQ(collected.arguments.size(), 1);
    EXPECT_EQ(collected.arguments[0], "{\"city\":\"Berlin\",\"days\":2}");
    EXPECT_TRUE(collected.content.empty());
}

TEST_F(Gemma4HereticOutputParserTest, TruncatedStringArgumentIsRecoveredOnGenerationEnd) {
    CollectedDeltas collected;

    feed(collected, "<|tool_call>", ov::genai::GenerationFinishReason::NONE);
    feed(collected,
        "call:editor{path:<|\"|>C:/tmp/report.json",
        ov::genai::GenerationFinishReason::NONE);
    // Heretic/abliterated models are more likely to stop before emitting the structural closure.
    feed(collected, "", ov::genai::GenerationFinishReason::STOP);

    ASSERT_EQ(collected.names.size(), 1);
    EXPECT_EQ(collected.names[0], "editor");
    ASSERT_EQ(collected.arguments.size(), 1);
    EXPECT_EQ(collected.arguments[0], "{\"path\":\"C:/tmp/report.json\"}");
    EXPECT_TRUE(collected.content.empty());
}

TEST_F(Gemma4HereticOutputParserTest, TruncatedBareValueIsRecoveredOnGenerationEnd) {
    CollectedDeltas collected;

    feed(collected, "<|tool_call>", ov::genai::GenerationFinishReason::NONE);
    feed(collected, "call:set_count{count:42", ov::genai::GenerationFinishReason::NONE);
    feed(collected, "", ov::genai::GenerationFinishReason::STOP);

    ASSERT_EQ(collected.names.size(), 1);
    EXPECT_EQ(collected.names[0], "set_count");
    ASSERT_EQ(collected.arguments.size(), 1);
    EXPECT_EQ(collected.arguments[0], "{\"count\":42}");
    EXPECT_TRUE(collected.content.empty());
}

TEST_F(Gemma4HereticOutputParserTest, UnaryToolCallAcceptsTurnEndAsKnownGemma4TerminatorDeviation) {
    const std::string input =
        "<|tool_call>call:get_weather{city:<|\"|>Berlin<|\"|>}<turn|>";
    auto generatedTensor = hereticTokenizer->encode(input).input_ids;
    std::vector<int64_t> generatedTokens(
        generatedTensor.data<int64_t>(),
        generatedTensor.data<int64_t>() + generatedTensor.get_size());

    ParsedOutput parsed = parser->parse(generatedTokens, true);

    ASSERT_EQ(parsed.toolCalls.size(), 1);
    EXPECT_EQ(parsed.toolCalls[0].name, "get_weather");
    EXPECT_EQ(parsed.toolCalls[0].arguments, "{\"city\":\"Berlin\"}");
    EXPECT_TRUE(parsed.content.empty());
}

}  // namespace
