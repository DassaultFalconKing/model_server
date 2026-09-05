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
#include <cctype>
#include <memory>
#include <optional>
#include <string>
#include <tuple>
#include <utility>
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

namespace {
struct CollectedDeltas {
    std::string content;
    std::string reasoning;
    std::string allJson;
    std::vector<std::string> toolNames;
    std::vector<std::string> toolArguments;
};

void accumulate(CollectedDeltas& out, const std::optional<rapidjson::Document>& doc) {
    if (!doc.has_value())
        return;
    const std::string serialized = serialize(doc);
    out.allJson += serialized;
    const rapidjson::Value& delta = (*doc)["delta"];
    if (!delta.IsObject())
        return;
    if (delta.HasMember("content") && delta["content"].IsString())
        out.content += delta["content"].GetString();
    if (delta.HasMember("reasoning_content") && delta["reasoning_content"].IsString())
        out.reasoning += delta["reasoning_content"].GetString();
    if (delta.HasMember("tool_calls") && delta["tool_calls"].IsArray()) {
        for (const auto& call : delta["tool_calls"].GetArray()) {
            if (!call.IsObject())
                continue;
            if (call.HasMember("function") && call["function"].IsObject()) {
                const auto& fn = call["function"];
                if (fn.HasMember("name") && fn["name"].IsString())
                    out.toolNames.push_back(fn["name"].GetString());
                if (fn.HasMember("arguments") && fn["arguments"].IsString())
                    out.toolArguments.push_back(fn["arguments"].GetString());
            }
        }
    }
}

OutputParser makeParser(ov::genai::Tokenizer& tokenizer) {
    const ToolsSchemas_t emptyToolsSchema{};
    return OutputParser(tokenizer, "gemma4", "gemma4", emptyToolsSchema);
}

void feed(OutputParser& parser, CollectedDeltas& out, const std::string& chunk, ov::genai::GenerationFinishReason finishReason = ov::genai::GenerationFinishReason::NONE) {
    accumulate(out, parser.parseChunk(chunk, {}, true, ov::genai::GenerationFinishReason::NONE));
    for (int i = 0; i < 32; ++i) {
        auto delta = parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::NONE);
        if (!delta.has_value())
            break;
        accumulate(out, delta);
    }
    if (finishReason != ov::genai::GenerationFinishReason::NONE) {
        accumulate(out, parser.parseChunk("", {}, true, finishReason));
        for (int i = 0; i < 8; ++i) {
            auto delta = parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::NONE);
            if (!delta.has_value())
                break;
            accumulate(out, delta);
        }
    }
}

std::vector<std::pair<std::string, std::string>> splitsOf(const std::string& marker) {
    std::vector<std::pair<std::string, std::string>> splits;
    for (size_t i = 1; i < marker.size(); ++i)
        splits.emplace_back(marker.substr(0, i), marker.substr(i));
    return splits;
}

bool containsAnyMarkerFragment(const std::string& text, const std::string& marker) {
    if (text.find(marker) != std::string::npos)
        return true;
    for (size_t i = 1; i < marker.size(); ++i) {
        if (text.find(marker.substr(0, i)) != std::string::npos)
            return true;
    }
    return false;
}
}  // namespace

class Gemma4MarkerSplitTest : public ::testing::TestWithParam<std::tuple<std::string, std::string, std::string>> {};

TEST_P(Gemma4MarkerSplitTest, PartialPrefixIsHeldAndBytesAreNeitherLostNorDuplicated) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    const auto [marker, prefix, suffix] = GetParam();

    if (marker == "<|tool_call>") {
        CollectedDeltas out;
        accumulate(out, parser.parseChunk("prelude", {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(out, parser.parseChunk(prefix, {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_FALSE(containsAnyMarkerFragment(out.content, marker)) << "prefix leaked into content: " << prefix;
        EXPECT_FALSE(containsAnyMarkerFragment(out.reasoning, marker)) << "prefix leaked into reasoning: " << prefix;
        feed(parser, out, suffix + "call:ls{a:true}");
        feed(parser, out, "<tool_call|>");
        feed(parser, out, "tail");
        ASSERT_FALSE(out.toolNames.empty()) << "split=" << prefix << "+" << suffix << " json=" << out.allJson;
        EXPECT_EQ(out.toolNames.front(), "ls");
        ASSERT_FALSE(out.toolArguments.empty());
        EXPECT_EQ(out.toolArguments.back(), "{\"a\":true}");
        EXPECT_NE(out.content.find("prelude"), std::string::npos);
        EXPECT_NE(out.content.find("tail"), std::string::npos);
        EXPECT_EQ(out.content.find(marker), std::string::npos);
        EXPECT_EQ(out.reasoning.find(marker), std::string::npos);
    } else if (marker == "<tool_call|>") {
        CollectedDeltas out;
        feed(parser, out, "<|tool_call>call:ls{a:true}");
        accumulate(out, parser.parseChunk(prefix, {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_EQ(out.content.find(prefix), std::string::npos) << "partial end tag leaked: " << prefix;
        accumulate(out, parser.parseChunk(suffix, {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(out, parser.parseChunk("tail", {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_NE(out.content.find("tail"), std::string::npos) << out.allJson;
        EXPECT_EQ(out.content.find(marker), std::string::npos);
        ASSERT_FALSE(out.toolArguments.empty());
        EXPECT_EQ(out.toolArguments.back(), "{\"a\":true}");
    } else if (marker == "<channel|>") {
        CollectedDeltas reasoning;
        accumulate(reasoning, parser.parseChunk("<|channel>thought\nheld", {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(reasoning, parser.parseChunk(prefix, {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_EQ(reasoning.reasoning.find(prefix), std::string::npos) << "partial <channel|> leaked: " << prefix << " json=" << reasoning.allJson;
        accumulate(reasoning, parser.parseChunk(suffix, {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(reasoning, parser.parseChunk("visible", {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_NE(reasoning.reasoning.find("held"), std::string::npos) << reasoning.allJson;
        EXPECT_EQ(reasoning.reasoning.find(marker), std::string::npos);
        EXPECT_NE(reasoning.content.find("visible"), std::string::npos) << reasoning.allJson;
        EXPECT_EQ(reasoning.content.find(marker), std::string::npos);
    } else {
        CollectedDeltas out;
        accumulate(out, parser.parseChunk("prelude", {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(out, parser.parseChunk(prefix, {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_FALSE(containsAnyMarkerFragment(out.content, marker)) << "prefix leaked into content: " << prefix << " content=" << out.content;
        accumulate(out, parser.parseChunk(suffix, {}, true, ov::genai::GenerationFinishReason::NONE));
        accumulate(out, parser.parseChunk("tail", {}, true, ov::genai::GenerationFinishReason::NONE));
        EXPECT_EQ(out.content.find(marker), std::string::npos) << marker << " leaked into content=" << out.content;
        EXPECT_NE(out.content.find("prelude"), std::string::npos);
        EXPECT_NE(out.content.find("tail"), std::string::npos);
        EXPECT_EQ(out.content.find("preludeprelude"), std::string::npos);
        EXPECT_EQ(out.content.find("tailtail"), std::string::npos);
    }
}

std::vector<std::tuple<std::string, std::string, std::string>> markerSplitParams() {
    std::vector<std::tuple<std::string, std::string, std::string>> params;
    for (const std::string& marker : {"<|tool_call>", "<tool_call|>", "<channel|>", "<turn|>", "<|tool_response>"}) {
        for (const auto& [prefix, suffix] : splitsOf(marker))
            params.emplace_back(marker, prefix, suffix);
    }
    return params;
}

INSTANTIATE_TEST_SUITE_P(
    ExhaustiveByteCuts,
    Gemma4MarkerSplitTest,
    ::testing::ValuesIn(markerSplitParams()));

TEST(Gemma4StreamingHardeningTest, FinishAfterPartialToolStartDoesNotInventToolCall) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    accumulate(out, parser.parseChunk("<|tool_", {}, true, ov::genai::GenerationFinishReason::NONE));
    accumulate(out, parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::STOP));
    EXPECT_TRUE(out.toolNames.empty());
    EXPECT_TRUE(out.toolArguments.empty());
    EXPECT_EQ(out.content.find("<|tool_call>"), std::string::npos);
    EXPECT_EQ(out.reasoning.find("<|tool_call>"), std::string::npos);
}

TEST(Gemma4StreamingHardeningTest, FinishInsideUnclosedQuotedWindowsPathDoesNotInventStructure) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    accumulate(out, parser.parseChunk("<|tool_call>call:read_file{path:<|\"|>C:\\foo", {}, true, ov::genai::GenerationFinishReason::NONE));
    accumulate(out, parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::STOP));
    for (const auto& args : out.toolArguments) {
        rapidjson::Document parsed;
        parsed.Parse(args.c_str());
        EXPECT_FALSE(parsed.HasParseError()) << args;
    }
}

TEST(Gemma4StreamingHardeningTest, FinishAfterOpenArgsObjectDoesNotEmitEmptyToolCalls) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    accumulate(out, parser.parseChunk("<|tool_call>call:get_time{", {}, true, ov::genai::GenerationFinishReason::NONE));
    accumulate(out, parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::STOP));
    EXPECT_TRUE(out.toolArguments.empty()) << out.allJson;
}

TEST(Gemma4StreamingHardeningTest, FinishAfterPartialEndTagDoesNotEmitEmptyToolCalls) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out, "<|tool_call>call:get_time{}");
    accumulate(out, parser.parseChunk("<tool_", {}, true, ov::genai::GenerationFinishReason::NONE));
    accumulate(out, parser.parseChunk("", {}, true, ov::genai::GenerationFinishReason::STOP));
    ASSERT_EQ(out.toolNames.size(), 1u);
    EXPECT_EQ(out.toolNames.front(), "get_time");
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{}");
    EXPECT_EQ(out.content.find("<tool_"), std::string::npos);
}

TEST(Gemma4StreamingHardeningTest, EmptyArgsAreEmptyJsonObject) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out, "<|tool_call>call:get_time{}<tool_call|>", ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolNames.size(), 1u);
    EXPECT_EQ(out.toolNames.front(), "get_time");
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{}");
}

TEST(Gemma4StreamingHardeningTest, NestedObjectPreservesTypes) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out, "<|tool_call>call:cfg{config:{enabled:true,nested:{count:3}}}<tool_call|>", ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{\"config\":{\"enabled\":true,\"nested\":{\"count\":3}}}");
}

TEST(Gemma4StreamingHardeningTest, ArrayTagsRemainJsonArray) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out,
         "<|tool_call>call:tag{tags:[<|\"|>runtime<|\"|>,<|\"|>windows<|\"|>]}<tool_call|>",
         ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{\"tags\":[\"runtime\",\"windows\"]}");
}

TEST(Gemma4StreamingHardeningTest, WindowsPathsRemainJsonArrayNotStringifiedJson) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out,
         "<|tool_call>call:list{paths:[<|\"|>C:\\llm\\ovms.exe<|\"|>,<|\"|>C:\\llm\\README.md<|\"|>]}<tool_call|>",
         ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{\"paths\":[\"C:\\\\llm\\\\ovms.exe\",\"C:\\\\llm\\\\README.md\"]}");
    EXPECT_EQ(out.toolArguments.front().front(), '{');
    EXPECT_EQ(out.toolArguments.front().find("\"[\\\""), std::string::npos);
}

TEST(Gemma4StreamingHardeningTest, MultilineWriteFileRoundtrip) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    std::string payload = "function test(x) {\n    const value = {\"a\": [1, 2, 3]};\n    return \"x,y:{z}\" + x;\n}\n";
    payload += std::string("'\n{\n}\n[\n]\n,\n:\n\\\n\\n\n|\n");
    while (payload.size() < 4096)
        payload += "line " + std::to_string(payload.size()) + " filler\n";
    const std::string chunk = "<|tool_call>call:write_file{content:<|\"|>" + payload + "<|\"|>}<tool_call|>";
    CollectedDeltas out;
    feed(parser, out, chunk, ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolNames.size(), 1u);
    EXPECT_EQ(out.toolNames.front(), "write_file");
    ASSERT_EQ(out.toolArguments.size(), 1u);
    rapidjson::Document parsed;
    parsed.Parse(out.toolArguments.front().c_str());
    ASSERT_FALSE(parsed.HasParseError()) << out.toolArguments.front();
    ASSERT_TRUE(parsed.IsObject());
    ASSERT_TRUE(parsed.HasMember("content"));
    ASSERT_TRUE(parsed["content"].IsString());
    EXPECT_EQ(std::string(parsed["content"].GetString(), parsed["content"].GetStringLength()), payload);
}

TEST(Gemma4StreamingHardeningTest, ShellCommandWithQuotesPipesAndWindowsPath) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    const std::string cmd = "powershell -Command \"Get-Content 'C:\\llm\\a.json' | %{ $_ }\"";
    CollectedDeltas out;
    feed(parser, out, "<|tool_call>call:run_command{cmd:<|\"|>" + cmd + "<|\"|>}<tool_call|>", ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolArguments.size(), 1u);
    rapidjson::Document parsed;
    parsed.Parse(out.toolArguments.front().c_str());
    ASSERT_FALSE(parsed.HasParseError()) << out.toolArguments.front();
    EXPECT_EQ(std::string(parsed["cmd"].GetString()), cmd);
}

TEST(Gemma4StreamingHardeningTest, TwoConsecutiveToolCallsKeepIndices) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out, "<|tool_call>call:a{x:1}<tool_call|>");
    feed(parser, out, "<|tool_call>call:b{y:2}<tool_call|>", ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolNames.size(), 2u);
    EXPECT_EQ(out.toolNames[0], "a");
    EXPECT_EQ(out.toolNames[1], "b");
    ASSERT_GE(out.toolArguments.size(), 2u);
    EXPECT_EQ(out.toolArguments[0], "{\"x\":1}");
    EXPECT_EQ(out.toolArguments[1], "{\"y\":2}");
}

TEST(Gemma4StreamingHardeningTest, ReasoningImplicitlyEndsOnSplitToolStartWithoutChannelEnd) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out, "<|channel>thought\nМне надо посмотреть файл.");
    feed(parser, out, "<|tool_");
    feed(parser, out, "call>call:read_file{");
    feed(parser, out, "path:<|\"|>C:\\llm\\README.md<|\"|>}");
    feed(parser, out, "<tool_call|>", ov::genai::GenerationFinishReason::STOP);
    EXPECT_NE(out.reasoning.find("Мне надо посмотреть файл."), std::string::npos) << out.allJson;
    EXPECT_EQ(out.reasoning.find("<|tool_call>"), std::string::npos) << out.reasoning;
    EXPECT_EQ(out.reasoning.find("<|tool_"), std::string::npos) << out.reasoning;
    EXPECT_EQ(out.content.find("<|tool_call>"), std::string::npos) << out.content;
    ASSERT_FALSE(out.toolNames.empty()) << out.allJson;
    EXPECT_EQ(out.toolNames.front(), "read_file");
    ASSERT_FALSE(out.toolArguments.empty());
    EXPECT_EQ(out.toolArguments.back(), "{\"path\":\"C:\\\\llm\\\\README.md\"}");
}

TEST(Gemma4StreamingHardeningTest, GuidedJsonArgumentsRemainStructured) {
    ov::genai::Tokenizer tokenizer(tokenizerPath);
    OutputParser parser = makeParser(tokenizer);
    CollectedDeltas out;
    feed(parser, out,
         "<|tool_call>call:example_tool{\"arg1\":\"value1\",\"arg2\":42,\"nested\":{\"enabled\":true},\"paths\":[\"C:\\\\llm\\\\ovms.exe\",\"C:\\\\llm\\\\README.md\"]}<tool_call|>",
         ov::genai::GenerationFinishReason::STOP);
    ASSERT_EQ(out.toolNames.size(), 1u);
    EXPECT_EQ(out.toolNames.front(), "example_tool");
    ASSERT_EQ(out.toolArguments.size(), 1u);
    EXPECT_EQ(out.toolArguments.front(), "{\"arg1\":\"value1\",\"arg2\":42,\"nested\":{\"enabled\":true},\"paths\":[\"C:\\\\llm\\\\ovms.exe\",\"C:\\\\llm\\\\README.md\"]}");
}
