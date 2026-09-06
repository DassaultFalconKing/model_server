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

#include "../../../llm/io_processing/gemma4/gemma4_tool_parser.hpp"

using namespace ovms;

TEST(Gemma4NestedArgsTest, NestedObjectPreservesInnerKeysAndTypes) {
    const std::string input =
        "{all:true,filters:{language:<|\"|>python<|\"|>,min_stars:100}}";

    EXPECT_EQ(
        Gemma4ToolParser::normalizeArgStr(input),
        "{\"all\":true,\"filters\":{\"language\":\"python\",\"min_stars\":100}}");
}

TEST(Gemma4NestedArgsTest, MixedArrayPreservesStringsBareScalarsAndObjects) {
    const std::string input =
        "[<|\"|>alpha<|\"|>,2,false,null,{kind:<|\"|>local<|\"|>},[3,<|\"|>four<|\"|>]]";

    EXPECT_EQ(
        Gemma4ToolParser::normalizeArgStr(input),
        "[\"alpha\",2,false,null,{\"kind\":\"local\"},[3,\"four\"]]");
}

TEST(Gemma4NestedArgsTest, StringPayloadMayContainJsonStructuralCharacters) {
    const std::string input =
        "{code:<|\"|>if (x) { return [1,2]; }<|\"|>,enabled:true}";

    EXPECT_EQ(
        Gemma4ToolParser::normalizeArgStr(input),
        "{\"code\":\"if (x) { return [1,2]; }\",\"enabled\":true}");
}
