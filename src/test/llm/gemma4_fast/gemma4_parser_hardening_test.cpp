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
#include <rapidjson/document.h>

#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../../llm/io_processing/gemma4/gemma4_tool_parser.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

#ifdef _WIN32
const std::string hardeningTokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string hardeningTokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

namespace {
const std::string questionSchema = R"({"type":"object","properties":{"value":{},"path":{"type":"string"},"text":{"type":"string"}}})";

struct ParsedDirect {
    std::string content;
    std::vector<ToolCallDelta> toolCalls;
};

class Gemma4ParserHardeningTest : public ::testing::Test {
protected:
    static std::unique_ptr<ov::genai::Tokenizer> tokenizer;

    static void SetUpTestSuite() {
        const char* configured = std::getenv("GEMMA4_TOKENIZER_PATH");
        tokenizer = std::make_unique<ov::genai::Tokenizer>(configured ? configured : hardeningTokenizerPath);
    }

    static void TearDownTestSuite() {
        tokenizer.reset();
    }

    static ToolsSchemas_t questionTools() {
        ToolsSchemas_t tools;
        tools.emplace("question", ToolSchemaWrapper{nullptr, questionSchema});
        return tools;
    }

    static void collectDelta(ParsedDirect& parsed, const std::optional<Delta>& delta) {
        if (!delta.has_value())
            return;
        std::visit([&](const auto& value) {
            using T = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<T, ContentDelta>) {
                parsed.content.append(value.text);
            } else if constexpr (std::is_same_v<T, ToolCallDelta>) {
                parsed.toolCalls.push_back(value);
            }
        }, *delta);
    }

    ParsedDirect parseChunks(const std::vector<std::string>& chunks) {
        Gemma4ToolParser parser(*tokenizer, questionTools());
        ParsedDirect parsed;
        for (const auto& chunk : chunks) {
            for (int phase = 0; phase < 12; ++phase) {
                auto delta = parser.parseChunk(phase == 0 ? chunk : "", {}, ov::genai::GenerationFinishReason::NONE);
                collectDelta(parsed, delta);
            }
        }
        for (int phase = 0; phase < 12; ++phase) {
            auto delta = parser.parseChunk("", {}, ov::genai::GenerationFinishReason::STOP);
            collectDelta(parsed, delta);
        }
        return parsed;
    }

    void assertArgumentsObject(const std::string& arguments, rapidjson::Document& doc) {
        doc.Parse(arguments.c_str());
        ASSERT_FALSE(doc.HasParseError()) << arguments;
        ASSERT_TRUE(doc.IsObject()) << arguments;
    }
};

std::unique_ptr<ov::genai::Tokenizer> Gemma4ParserHardeningTest::tokenizer;
}  // namespace

TEST_F(Gemma4ParserHardeningTest, MalformedNumericLookingScalarsDoNotEmitInvalidJson) {
    for (const std::string malformed : {"1e", "-", "1foo", "--1", "01"}) {
        SCOPED_TRACE(malformed);
        auto parsed = parseChunks({"<|tool_call>call:question{value:" + malformed + "}<tool_call|>"});
        ASSERT_LE(parsed.toolCalls.size(), 1u);
        if (parsed.toolCalls.empty())
            continue;
        rapidjson::Document doc;
        assertArgumentsObject(parsed.toolCalls[0].arguments, doc);
        ASSERT_TRUE(doc.HasMember("value"));
        ASSERT_TRUE(doc["value"].IsString());
        EXPECT_EQ(std::string(doc["value"].GetString(), doc["value"].GetStringLength()), malformed);
    }
}

TEST_F(Gemma4ParserHardeningTest, ValidLargeJsonNumbersStayLexicallyLossless) {
    const std::vector<std::string> numbers{
        "18446744073709551617",
        "-9223372036854775809",
        "0.123456789012345678901",
        "1e400",
        "-0",
    };
    for (const auto& number : numbers) {
        SCOPED_TRACE(number);
        auto parsed = parseChunks({"<|tool_call>call:question{value:" + number + "}<tool_call|>"});
        ASSERT_EQ(parsed.toolCalls.size(), 1u);
        EXPECT_EQ(parsed.toolCalls[0].arguments, "{\"value\":" + number + "}");
        rapidjson::Document doc;
        assertArgumentsObject(parsed.toolCalls[0].arguments, doc);
    }
}

TEST_F(Gemma4ParserHardeningTest, IncompleteBareCallsRemainVisibleContentAtFinish) {
    const std::vector<std::string> prose{
        "call:foo is not a command",
        "call:foo",
        "  call:foo is documentation",
        "call:question",
    };
    for (const auto& text : prose) {
        SCOPED_TRACE(text);
        auto parsed = parseChunks({text});
        EXPECT_TRUE(parsed.toolCalls.empty());
        EXPECT_EQ(parsed.content, text);
    }
}

TEST_F(Gemma4ParserHardeningTest, FragmentedBareCallProseDoesNotDisappear) {
    auto parsed = parseChunks({"call:fo", "o is ordinary prose"});
    EXPECT_TRUE(parsed.toolCalls.empty());
    EXPECT_EQ(parsed.content, "call:foo is ordinary prose");
}

TEST_F(Gemma4ParserHardeningTest, CompleteBareAndCanonicalControlsStillParse) {
    for (const auto& chunks : std::vector<std::vector<std::string>>{
             {"call:question{value:1}"},
             {"call:quest", "ion{value:1}"},
             {"<|tool_call>call:question{value:1}<tool_call|>"},
         }) {
        auto parsed = parseChunks(chunks);
        ASSERT_EQ(parsed.toolCalls.size(), 1u);
        ASSERT_TRUE(parsed.toolCalls[0].name.has_value());
        EXPECT_EQ(parsed.toolCalls[0].name.value(), "question");
        EXPECT_EQ(parsed.toolCalls[0].arguments, R"({"value":1})");
    }
}

TEST_F(Gemma4ParserHardeningTest, PreservesWindowsPathArgumentsByteForByte) {
    struct Case {
        std::string input;
        std::string expected;
    };
    const std::vector<Case> cases{
        {R"(<|tool_call>call:question{path:<|"|>C:\git\g4-final-review<|"|>}<tool_call|>)", R"(C:\git\g4-final-review)"},
        {R"(<|tool_call>call:question{"path":"C:\\git\\g4-final-review"}<tool_call|>)", R"(C:\git\g4-final-review)"},
        {R"(<|tool_call>call:question{path:<|"|>C:/git/g4-final-review<|"|>}<tool_call|>)", "C:/git/g4-final-review"},
    };

    for (const auto& testCase : cases) {
        SCOPED_TRACE(testCase.input);
        auto parsed = parseChunks({testCase.input});
        ASSERT_EQ(parsed.toolCalls.size(), 1u);
        ASSERT_TRUE(parsed.toolCalls[0].name.has_value());
        EXPECT_EQ(parsed.toolCalls[0].name.value(), "question");
        rapidjson::Document doc;
        assertArgumentsObject(parsed.toolCalls[0].arguments, doc);
        ASSERT_TRUE(doc.HasMember("path"));
        ASSERT_TRUE(doc["path"].IsString());
        EXPECT_EQ(std::string(doc["path"].GetString(), doc["path"].GetStringLength()), testCase.expected);
    }
}

TEST_F(Gemma4ParserHardeningTest, ParserOutputJsonValidityInvariantCorpus) {
    struct CorpusCase {
        std::vector<std::string> chunks;
        bool requireCall;
        bool requireNoCall;
        std::optional<std::string> expectedContent;
    };

    const std::vector<CorpusCase> cases{
        {{"<|tool_call>call:question{value:1e}<tool_call|>"}, false, false, std::nullopt},
        {{"<|tool_call>call:question{value:-}<tool_call|>"}, false, false, std::nullopt},
        {{"<|tool_call>call:question{text:\"unterminated}<tool_call|>"}, false, true, std::nullopt},
        {{"<|tool_call>call:question{value:{x:1}<tool_call|>"}, false, true, std::nullopt},
        {{"<|tool_call>call:question{value:[1}}<tool_call|>"}, false, true, std::nullopt},
        {{"<|tool_call>call:question{value:[1<tool_call|>"}, false, true, std::nullopt},
        {{R"(<|tool_call>call:question{text:<|"|>call:foo<|"|>}<tool_call|>)"}, true, false, std::nullopt},
        {{"literal <|tool_call> example"}, false, true, "literal <|tool_call> example"},
        {{"call:foo"}, false, true, "call:foo"},
        {{"call:foo is ordinary prose"}, false, true, "call:foo is ordinary prose"},
        {{"<|tool_call>call:question{value:1}<tool_call|>"}, true, false, std::nullopt},
        {{"call:question{value:1}"}, true, false, std::nullopt},
    };

    for (const auto& testCase : cases) {
        SCOPED_TRACE(testCase.chunks.front());
        auto parsed = parseChunks(testCase.chunks);
        if (testCase.requireNoCall)
            EXPECT_TRUE(parsed.toolCalls.empty());
        if (testCase.requireCall)
            ASSERT_EQ(parsed.toolCalls.size(), 1u);
        if (testCase.expectedContent.has_value())
            EXPECT_EQ(parsed.content, testCase.expectedContent.value());
        for (const auto& call : parsed.toolCalls) {
            rapidjson::Document doc;
            assertArgumentsObject(call.arguments, doc);
        }
    }
}
