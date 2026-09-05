// Copyright 2026 Intel Corporation
// Licensed under the Apache License, Version 2.0.

#include <gtest/gtest.h>
#include <memory>
#include <string>
#include <vector>

#include "../../../llm/io_processing/gemma4/gemma4_tool_parser.hpp"
#include "../../../llm/io_processing/output_parser.hpp"
#include "../../platform_utils.hpp"
#include "output_parser_test_utils.hpp"

using namespace ovms;

class Gemma4ReviewedContractTest : public ::testing::Test {
protected:
    static std::unique_ptr<ov::genai::Tokenizer> tokenizer;
    static void SetUpTestSuite() {
        tokenizer = std::make_unique<ov::genai::Tokenizer>(getGenericFullPathForSrcTest(
            "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov"));
    }
    static void TearDownTestSuite() { tokenizer.reset(); }

    // The leaf API emits one delta per invocation. Drain buffered states separately
    // from feeding bytes; this tests boundary scanning, not the streamer's schedule.
    static std::string parseArguments(const std::vector<std::string>& chunks) {
        Gemma4ToolParser parser(*tokenizer);
        std::string args;
        auto collect = [&](const std::optional<Delta>& delta) {
            if (delta) {
                if (const auto* tool = std::get_if<ToolCallDelta>(&*delta))
                    args += tool->arguments;
            }
        };
        for (const auto& chunk : chunks)
            collect(parser.parseChunk(chunk, {}, ov::genai::GenerationFinishReason::NONE));
        for (int i = 0; i < 8; ++i)
            collect(parser.parseChunk("", {}, ov::genai::GenerationFinishReason::STOP));
        return args;
    }

    static ParsedOutput stream(const std::string& text, const std::string& toolName = "gemma4",
        const std::string& reasoningName = "gemma4") {
        OutputParser parser(*tokenizer, toolName, reasoningName, {});
        auto ids = tokenizer->encode(text, ov::genai::add_special_tokens(false)).input_ids;
        return ovms::test::parseWithStreamer(*tokenizer, parser,
            {ids.data<int64_t>(), ids.data<int64_t>() + ids.get_size()}, true, true);
    }
};

std::unique_ptr<ov::genai::Tokenizer> Gemma4ReviewedContractTest::tokenizer;

TEST_F(Gemma4ReviewedContractTest, GuidedJsonEveryByteSplitPreservesStringsAndTypes) {
    const std::vector<std::string> payloads = {
        R"({"s":"{"})", R"({"s":"}"})", R"({"s":"["})", R"({"s":"]"})",
        R"({"path":"C:\\temp\\"})", R"({"s":"a\"b"})", R"({"s":"a\\\"b"})",
        R"({"s":"a\\\\","t":"{},[]:'\""})",
        R"({"nested":{"a":[null,true,false,1,1.5,"x",{"y":[]}]},"empty":{}})",
        R"({"s":"line1\nline2\tline3","nul":"\u0000"})", "{}"};
    for (const auto& payload : payloads) {
        const std::string text = "<|tool_call>call:f" + payload + "<tool_call|>";
        for (size_t cut = text.find('{') + 1; cut < text.size(); ++cut) {
            SCOPED_TRACE(payload + " cut=" + std::to_string(cut));
            EXPECT_EQ(parseArguments({text.substr(0, cut), text.substr(cut)}), payload);
        }
        auto result = stream(text);
        ASSERT_EQ(result.toolCalls.size(), 1u) << payload;
        EXPECT_EQ(result.toolCalls[0].arguments, payload);
        EXPECT_TRUE(result.content.empty());
    }
}

TEST_F(Gemma4ReviewedContractTest, GuidedJsonTruncationNeverFabricatesArguments) {
    const std::string payload = R"({"s":"a\\\"}b","nested":[{"x":true}]})";
    for (size_t cut = 1; cut < payload.size(); ++cut) {
        SCOPED_TRACE(cut);
        EXPECT_TRUE(parseArguments({"<|tool_call>call:f" + payload.substr(0, cut)}).empty());
    }
}

TEST_F(Gemma4ReviewedContractTest, GuidedJsonTruncationDoesNotExposeExecutableToolCall) {
    Gemma4ToolParser parser(*tokenizer);
    const std::string truncated = R"(<|tool_call>call:write_file{"path":"output.txt","content":"unterminated)";

    auto assertNoToolDelta = [](const std::optional<Delta>& delta) {
        if (delta.has_value())
            EXPECT_EQ(std::get_if<ToolCallDelta>(&*delta), nullptr);
    };

    assertNoToolDelta(parser.parseChunk(truncated, {}, ov::genai::GenerationFinishReason::NONE));
    for (int i = 0; i < 4; ++i)
        assertNoToolDelta(parser.parseChunk("", {}, ov::genai::GenerationFinishReason::STOP));
}

TEST_F(Gemma4ReviewedContractTest, CompleteBufferedGuidedJsonEmitsWholeToolCallOnFinalFlush) {
    Gemma4ToolParser parser(*tokenizer);
    const std::string complete = R"(<|tool_call>call:write_file{"path":"output.txt","content":"ok"}<tool_call|>)";

    EXPECT_FALSE(parser.parseChunk(complete, {}, ov::genai::GenerationFinishReason::NONE).has_value());
    const auto delta = parser.parseChunk("", {}, ov::genai::GenerationFinishReason::STOP);
    ASSERT_TRUE(delta.has_value());
    const auto* tool = std::get_if<ToolCallDelta>(&*delta);
    ASSERT_NE(tool, nullptr);
    ASSERT_TRUE(tool->name.has_value());
    EXPECT_EQ(*tool->name, "write_file");
    EXPECT_EQ(tool->arguments, R"({"path":"output.txt","content":"ok"})");
}

TEST_F(Gemma4ReviewedContractTest, InvalidGuidedJsonCannotFallBackToNativeCoercion) {
    EXPECT_THROW(parseArguments({R"(<|tool_call>call:f{"s":}<tool_call|>)"}), std::runtime_error);
}

TEST_F(Gemma4ReviewedContractTest, NativeFallbackRemainsAvailable) {
    EXPECT_EQ(parseArguments({R"(<|tool_call>call:f{s:<|"|>a{b}c<|"|>,n:2}<tool_call|>)"}),
        R"({"s":"a{b}c","n":2})");
}

TEST_F(Gemma4ReviewedContractTest, StreamerKeepsNonGemmaToolExamplesInReasoning) {
    const std::string example = R"(Example: <tool_call>{"name":"f","arguments":{}}</tool_call> is an example.)";
    const auto result = stream("<think>" + example + "</think>Answer", "hermes3", "qwen3");
    EXPECT_TRUE(result.toolCalls.empty());
    EXPECT_EQ(result.reasoning, example);
    EXPECT_EQ(result.content, "Answer");
}

TEST_F(Gemma4ReviewedContractTest, StreamerTransitionsFromOpenGemmaReasoningToTools) {
    const auto result = stream(R"(<|channel>thought
Need a file.<|tool_call>call:read_file{"path":"C:\\llm\\README.md"}<tool_call|>)");
    EXPECT_EQ(result.reasoning, "Need a file.");
    EXPECT_TRUE(result.content.empty());
    ASSERT_EQ(result.toolCalls.size(), 1u);
    EXPECT_EQ(result.toolCalls[0].name, "read_file");
    EXPECT_EQ(result.toolCalls[0].arguments, R"({"path":"C:\\llm\\README.md"})");
}
