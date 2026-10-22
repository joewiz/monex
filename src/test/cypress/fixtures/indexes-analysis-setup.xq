xquery version "3.1";

(:
 : SPDX LGPL-2.1-or-later
 : Copyright (C) 2014 The eXist-db Authors
 :)

(: A collection whose Lucene configuration has analyzer chains, fields with and without expressions, fields that
 : aren't stored, and inline and ignore elements, for the indexes pane's spec. The fields' names are the spec's own,
 : as all collections share one index. :)

declare variable $collection-name := "monex-indexes-analysis-test";
declare variable $collection := "/db/" || $collection-name;
declare variable $config := "/db/system/config/db/" || $collection-name;

declare variable $xconf :=
    <collection xmlns="http://exist-db.org/collection-config/1.0">
        <index xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <lucene>
                <analyzer class="org.apache.lucene.analysis.standard.StandardAnalyzer"/>
                <analyzer id="stopped" class="org.apache.lucene.analysis.standard.StandardAnalyzer">
                    <param name="stopwords" type="org.apache.lucene.analysis.CharArraySet">
                        <value>the</value>
                        <value>of</value>
                    </param>
                </analyzer>
                <analyzer id="keyword" class="org.apache.lucene.analysis.core.KeywordAnalyzer"/>
                <analyzer id="cased">
                    <tokenizer name="standard"/>
                    <filter name="englishPossessive"/>
                    <filter name="asciiFolding"/>
                </analyzer>
                <analyzer id="delimited">
                    <index>
                        <tokenizer name="whitespace"/>
                        <filter name="wordDelimiterGraph" preserveOriginal="1" catenateAll="1"/>
                        <filter name="flattenGraph"/>
                        <filter name="lowercase"/>
                    </index>
                    <query>
                        <tokenizer name="whitespace"/>
                        <filter name="wordDelimiterGraph" preserveOriginal="1"/>
                        <filter name="lowercase"/>
                    </query>
                </analyzer>
                <analyzer id="stripped">
                    <char-filter name="htmlStrip"/>
                    <tokenizer name="standard"/>
                    <filter name="lowercase"/>
                </analyzer>
                <inline qname="b"/>
                <ignore qname="sic"/>
                <text qname="div" analyzer="stopped">
                    <ignore qname="note"/>
                    <inline qname="hi"/>
                    <field name="monex-ia-stored"/>
                    <field name="monex-ia-unstored" store="no"/>
                    <field name="monex-ia-head-unstored" expression="head" store="no"/>
                    <field name="monex-ia-dated" if="@when" expression="head" store="no"/>
                    <field name="monex-ia-year" expression="@when" type="xs:integer"/>
                    <field name="monex-ia-id" expression="@id" analyzer="keyword"/>
                    <field name="monex-ia-cased" expression="head" analyzer="cased"/>
                    <field name="monex-ia-delimited" expression="p" analyzer="delimited" store="no"/>
                </text>
                <text qname="note">
                    <field name="monex-ia-misnamed" analyzer="delimted"/>
                </text>
                <text qname="p" analyzer="stripped"/>
            </lucene>
        </index>
    </collection>;

declare variable $xml :=
    <volume>
        <div id="d1" when="1783">
            <head>Treaty of Paris</head>
            <p>The <hi>tre</hi>aty was signed<note>A note on the treaty</note> in Paris by the F-16 squadron.</p>
            <p>Both parties agreed.</p>
        </div>
        <div id="d2">
            <head>Peace of Paris</head>
            <p>Another treaty.</p>
        </div>
    </volume>;

(
    if (xmldb:collection-available($collection)) then xmldb:remove($collection) else (),
    if (xmldb:collection-available($config)) then xmldb:remove($config) else (),
    xmldb:create-collection("/db/system/config", "db"),
    xmldb:create-collection("/db/system/config/db", $collection-name),
    xmldb:store($config, "collection.xconf", $xconf),
    xmldb:create-collection("/db", $collection-name),
    xmldb:store($collection, "volume.xml", $xml),
    "ok"
)[last()]
