//*****************************************************************************
// Copyright 2026 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//*****************************************************************************

#include <gtest/gtest.h>
#include <openvino/genai/tokenizer.hpp>

#include <algorithm>
#include <memory>
#include <string>
#include <tuple>
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "output_parser_test_utils.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

namespace {
#ifdef _WIN32
const std::string tokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string tokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

const std::string emptySchema = R"({"type":"object","properties":{},"additionalProperties":false})";

// RED contract: after ownsToolCallBoundaries is enabled, CONTENT must keep routing
// through Gemma4ToolParser so later <|tool_call> / bare call: / <turn|> handling
// neither duplicates nor drops bytes relative to the chunk sequence.
class Gemma4ContentOwnsRoutingContractTest : public ::testing::Test {
protected:
    static std::unique_ptr<ov::genai::Tokenizer> tokenizer;

    static void SetUpTestSuite() {
        tokenizer = std::make_unique<ov::genai::Tokenizer>(tokenizerPath);
    }

    static void TearDownTestSuite() {
        tokenizer.reset();
    }

    static ToolsSchemas_t tools() {
        ToolsSchemas_t out;
        out.emplace("sort", ToolSchemaWrapper{nullptr, emptySchema});
        out.emplace("question", ToolSchemaWrapper{nullptr, emptySchema});
        out.emplace("empty_params", ToolSchemaWrapper{nullptr, emptySchema});
        return out;
    }
};

std::unique_ptr<ov::genai::Tokenizer> Gemma4ContentOwnsRoutingContractTest::tokenizer;

std::string joinDownstream(const std::vector<std::optional<std::string>>& deltas) {
    std::string joined;
    for (const auto& d : deltas) {
        if (!d.has_value())
            continue;
        joined += *d;
    }
    return joined;
}
}  // namespace

TEST_F(Gemma4ContentOwnsRoutingContractTest, UnknownToContentThenToolCallDoesNotDropOrDuplicateBytes) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", tools());
    const std::vector<std::tuple<std::string, ov::genai::GenerationFinishReason>> chunks{
        {"HELLO", ov::genai::GenerationFinishReason::NONE},
        {"_WORLD", ov::genai::GenerationFinishReason::NONE},
        {"<|tool_call>", ov::genai::GenerationFinishReason::NONE},
        {"call:sort{array:[1]}", ov::genai::GenerationFinishReason::NONE},
        {"<tool_call|>", ov::genai::GenerationFinishReason::STOP},
    };

    std::string inputConcat;
    std::string downstreamConcat;
    for (const auto& [chunk, finish] : chunks) {
        inputConcat += chunk;
        auto delta = parser.parseChunk(chunk, {}, true, finish);
        if (delta.has_value()) {
            if (const auto* content = std::get_if<ContentDelta>(&*delta))
                downstreamConcat += content->text;
            if (const auto* tool = std::get_if<ToolCallDelta>(&*delta)) {
                if (tool->name)
                    downstreamConcat += *tool->name;
                downstreamConcat += tool->arguments;
            }
        }
    }

    // Structural markers may be consumed by the tool parser, but ordinary prose
    // and tool arguments must appear exactly once downstream.
    EXPECT_NE(downstreamConcat.find("HELLO_WORLD"), std::string::npos);
    EXPECT_NE(downstreamConcat.find("sort"), std::string::npos);
    EXPECT_NE(downstreamConcat.find("\"array\":[1]"), std::string::npos);
    EXPECT_EQ(std::count(downstreamConcat.begin(), downstreamConcat.end(), 'H'), 1);
}

TEST_F(Gemma4ContentOwnsRoutingContractTest, ConsecutiveContentChunksStaySinglePass) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", tools());
    std::string content;
    for (const std::string chunk : {"A", "B", "C", "D"}) {
        auto delta = parser.parseChunk(chunk, {}, true, ov::genai::GenerationFinishReason::NONE);
        ASSERT_TRUE(delta.has_value());
        const auto* cd = std::get_if<ContentDelta>(&*delta);
        ASSERT_NE(cd, nullptr);
        content += cd->text;
    }
    EXPECT_EQ(content, "ABCD");
}

TEST_F(Gemma4ContentOwnsRoutingContractTest, ContentThenToolCallStartHandoff) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", tools());
    ASSERT_TRUE(parser.parseChunk("PREFIX", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    // Owning parser must accept the tool opener after CONTENT without leaking it
    // back through the generic content path.
    auto mid = parser.parseChunk("<|tool_call>", {}, true, ov::genai::GenerationFinishReason::NONE);
    EXPECT_FALSE(mid.has_value());
    auto done = parser.parseChunk("call:sort{array:[7]}<tool_call|>", {}, true, ov::genai::GenerationFinishReason::STOP);
    ASSERT_TRUE(done.has_value());
    const auto* tool = std::get_if<ToolCallDelta>(&*done);
    ASSERT_NE(tool, nullptr);
    ASSERT_TRUE(tool->name.has_value());
    EXPECT_EQ(*tool->name, "sort");
    EXPECT_EQ(tool->arguments, "{\"array\":[7]}");
}

TEST_F(Gemma4ContentOwnsRoutingContractTest, StreamingContentWithTurnTokenStripsOnce) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", tools());
    std::string content;
    for (const auto& [chunk, finish] : std::vector<std::tuple<std::string, ov::genai::GenerationFinishReason>>{
             {"This is", ov::genai::GenerationFinishReason::NONE},
             {" some content", ov::genai::GenerationFinishReason::NONE},
             {" with a turn token at the end.", ov::genai::GenerationFinishReason::NONE},
             {"<turn|>", ov::genai::GenerationFinishReason::STOP},
         }) {
        auto delta = parser.parseChunk(chunk, {}, true, finish);
        if (!delta.has_value())
            continue;
        if (const auto* cd = std::get_if<ContentDelta>(&*delta))
            content += cd->text;
    }
    EXPECT_EQ(content, "This is some content with a turn token at the end.");
    EXPECT_EQ(content.find("<turn|>"), std::string::npos);
}

TEST_F(Gemma4ContentOwnsRoutingContractTest, EmptyObjectArgsEmitCompleteCallInOneChunk) {
    OutputParser parser(*tokenizer, "gemma4", "gemma4", tools());
    EXPECT_FALSE(parser.parseChunk("<|tool_call>", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    EXPECT_FALSE(parser.parseChunk("call:empty_params", {}, true, ov::genai::GenerationFinishReason::NONE).has_value());
    auto delta = parser.parseChunk("{}", {}, true, ov::genai::GenerationFinishReason::NONE);
    ASSERT_TRUE(delta.has_value()) << "empty {} must complete the validated call in-chunk";
    const auto* tool = std::get_if<ToolCallDelta>(&*delta);
    ASSERT_NE(tool, nullptr);
    ASSERT_TRUE(tool->name.has_value());
    EXPECT_EQ(*tool->name, "empty_params");
    EXPECT_EQ(tool->arguments, "{}");
}
