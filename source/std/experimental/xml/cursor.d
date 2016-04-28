
module std.experimental.xml.cursor;

import std.experimental.xml.interfaces;
import std.experimental.xml.faststrings;

import std.range.primitives;
import std.typecons;

struct XMLCursor(P)
    if (isLowLevelParser!P)
{
    /++
    +   The type of input accepted by this parser,
    +   i.e., the one accepted by the underlying low level parser.
    +/
    alias InputType = P.InputType;
    
    /++ The type of characters in the input, as returned by the underlying low level parser. +/
    alias CharacterType = P.CharacterType;
    
    /++ The type of sequences of CharacterType, as returned by this parser +/
    alias StringType = CharacterType[];
    
    struct Attribute
    {
        StringType prefix, name, value;
    }
    struct NamespaceDeclaration
    {
        StringType prefix, namespace;
    }
    
    private P parser;
    private ElementType!P currentNode;
    private bool starting;
    private Attribute[] attributes;
    private NamespaceDeclaration[] namespaces;
    private bool attributesParsed;
    
    private void advanceInput()
    {
        currentNode = parser.front;
        parser.popFront();
        attributesParsed = false;
        attributes = [];
        namespaces = [];
    }
    
    /++
    +   Initializes this parser (and the underlying low level one) with the given input.
    +/
    void setSource(InputType input)
    {
        parser.setSource(input);
        if(!documentEnd)
        {
            advanceInput();
            if(currentNode.kind == currentNode.kind.PROCESSING && fastEqual(currentNode.content[0..3], "xml"))
                starting = true;
            else
            {
                // document without xml declaration???
                // we accept it, for now.
                // assert(0);
                starting = false;
            }
        }
    }
    
    /++ Returns whether the cursor is at the end of the document. +/
    bool documentEnd()
    {
        return parser.empty();
    }
    
    /++ Advances to the first child of the current node. +/
    void enter()
    {
        if(starting)
        {
            starting = false;
            advanceInput();
        }
        else if (hasChildren())
            advanceInput();
    }
    
    /++ Advances to the end of the parent of the current node. +/
    void exit()
    {
        while (next()) {}
        if (!documentEnd)
            advanceInput();
    }
    
    /++
    +   Advances to the next sibling of the current node.
    +   Returns whether it succeded. If it fails, either the
    +   document has ended or the only meaningful operation is exit().
    +/
    bool next()
    {
        if(documentEnd || starting)
            return false;
        else if (parser.front.kind == currentNode.kind.END_TAG)
            return false;
        else if (currentNode.kind != currentNode.kind.START_TAG)
            advanceInput();
        else
        {
            int count = 1;
            while (count > 0)
            {
                advanceInput();
                if (currentNode.kind == currentNode.kind.START_TAG)
                    count++;
                else if (currentNode.kind == currentNode.kind.END_TAG)
                    count--;
            }
            if(documentEnd)
                return false;
            advanceInput();
            if (currentNode.kind == currentNode.kind.END_TAG)
                return false;
        }
        return true;
    }
    
    /++ Returns whether the current node has children, and enter() can thus be used. +/
    bool hasChildren()
    {
        return starting ||
              (currentNode.kind == currentNode.kind.START_TAG && parser.front.kind != currentNode.kind.END_TAG);
    }
    
    /++ Returns the kind of the current node. +/
    XMLKind getKind() const
    {
        XMLKind result;
        if(starting)
            return XMLKind.DOCUMENT;
        else switch(currentNode.kind)
        {
            case currentNode.kind.DOCTYPE:
                result = XMLKind.DOCTYPE;
                break;
            case currentNode.kind.START_TAG:
                result = XMLKind.ELEMENT_START;
                break;
            case currentNode.kind.END_TAG:
                result = XMLKind.ELEMENT_END;
                break;
            case currentNode.kind.EMPTY_TAG:
                result = XMLKind.ELEMENT_EMPTY;
                break;
            case currentNode.kind.TEXT:
            case currentNode.kind.CDATA:
                result = XMLKind.TEXT;
                break;
            case currentNode.kind.COMMENT:
                result = XMLKind.COMMENT;
                break;
            case currentNode.kind.PROCESSING:
                result = XMLKind.PROCESSING_INSTRUCTION;
                break;
            default:
                break;
        }
        return result;
    }
    
    /++
    +   If the current node is an element, return its complete name;
    +   it it is a processing instruction, return its target;
    +   otherwise, the result is unspecified.
    +/
    StringType getName() const
    {
        int i;
        if (currentNode.kind != currentNode.kind.TEXT && 
            currentNode.kind != currentNode.kind.COMMENT &&
            currentNode.kind != currentNode.kind.CDATA)
        {
            if ((i = fastIndexOfAny(currentNode.content, " \r\n\t")) >= 0)
                return currentNode.content[0..i];
            else
                return currentNode.content[0..$];
        }
        else
            return [];
    }
    
    /++
    +   If the current node is an element, return its local name (without namespace prefix);
    +   otherwise, return the same result as getName().
    +/
    StringType getLocalName() const
    {
        auto name = getName();
        int colon = fastIndexOf(name, ':');
        if (colon != -1)
            return name[(colon+1)..$];
        else
            return name;
    }
    
    /++
    +   If the current node is an element, return its namespace prefix;
    +   otherwise, the result in unspecified;
    +/
    StringType getPrefix() const
    {
        int colon = fastIndexOf(getName(), ':');
        if (colon != -1)
            return currentNode.content[0..colon];
        else
            return [];
    }
    
    private void parseAttributeList()
    {
        attributesParsed = true;
        int nameEnd = fastIndexOfAny(currentNode.content, " \r\n\t");
        if (nameEnd < 0)
            return;
        int attStart = nameEnd;
        int delta = fastIndexOfNeither(currentNode.content[nameEnd..$], " \r\n\t>");
        while (delta != -1)
        {
            CharacterType[] prefix, name, value;
            attStart += delta;
            
            delta = fastIndexOfAny(currentNode.content[attStart..$], ":=");
            if (delta == -1)
            {
                // attribute without value nor prefix???
                assert(0);
            }
            int sep = attStart + delta;
            if (currentNode.content[sep] == ':')
            {
                prefix = currentNode.content[attStart..sep];
                attStart = sep + 1;
                delta = fastIndexOf(currentNode.content[attStart..$], '=');
                if (delta == -1)
                {
                    // attribute without value???
                    assert(0);
                }
                sep = attStart + delta;
            }
            
            name = currentNode.content[attStart..sep];
            delta = fastIndexOfAny(name, " \r\n\t");
            if (delta >= 0)
                name = name[0..delta];
            
            int attEnd;
            int quote;
            delta = (sep + 1 < currentNode.content.length) ? fastIndexOfNeither(currentNode.content[sep + 1..$], " \r\n\t") : -1;
            if (delta >= 0)
            {
                quote = sep + 1 + delta;
                if (currentNode.content[quote] == '"' || currentNode.content[quote] == '\'')
                {
                    delta = fastIndexOf(currentNode.content[(quote + 1)..$], currentNode.content[quote]);
                    if(delta == -1)
                    {
                        // attribute quotes never closed???
                        assert(0);
                    }
                    attEnd = quote + 1 + delta;
                }
                else
                {
                    // value not surrounded by quotes
                    assert(0);
                }
            }
            else
            {
                // attribute without value???
                assert(0);
            }
            value = currentNode.content[(quote + 1)..attEnd];
            
            if (prefix.length == 5 && fastEqual(prefix, "xmlns"))
                namespaces ~= NamespaceDeclaration(name, value);
            else
                attributes ~= Attribute(prefix, name, value);
            
            attStart = attEnd + 1;
            delta = fastIndexOfNeither(currentNode.content[attStart..$], " \r\t\n>");
        }
    }
    
    /++
    +   If the current node is an element, return its attributes as an array of triplets
    +   (prefix, name, value); if the current node is the document node, return the attributes
    +   of the xml declaration (encoding, version, ...); otherwise, return an empty array.
    +/
    Attribute[] getAttributes()
    {
        auto kind = currentNode.kind;
        if (kind == kind.START_TAG || kind == kind.PROCESSING)
        {
            if (!attributesParsed)
                parseAttributeList();
        }
        else
            namespaces = [];
        return attributes;
    }
    
    /++
    +   If the current node is an element, return a list of namespace bindings created in this element
    +   start tag, as an array of pairs (prefix, namespace); otherwise, return an empty array.
    +/
    NamespaceDeclaration[] getNamespaceDefinitions()
    {
        auto kind = currentNode.kind;
        if (kind == kind.START_TAG)
        {
            if (!attributesParsed)
                parseAttributeList();
        }
        else
            namespaces = [];
        return namespaces;
    }
    
    /++
    +   Return the text content of a CDATA section, a comment or a text node;
    +   in all other cases, the result in unspecified.
    +/
    StringType getText() const
    {
        return currentNode.content;
    }
}

unittest
{
    import std.stdio;
    import std.experimental.xml.lexers;
    import std.experimental.xml.parser;
    
    string xml = q{
    <?xml encoding = "utf-8" ?>
    <aaa xmlns:myns="something">
        <myns:bbb myns:att='>'>
            <!-- lol -->
            Lots of Text!
            On multiple lines!
        </myns:bbb>
        <![CDATA[ Ciaone! ]]>
        <ccc/>
    </aaa>
    };
    
    auto cursor = XMLCursor!(Parser!(SliceLexer!string))();
    cursor.setSource(xml);
    
    // <?xml encoding = "utf-8" ?>
    assert(cursor.getKind() == XMLKind.DOCUMENT);
    assert(cursor.getName() == "xml");
    assert(cursor.getPrefix() == "");
    assert(cursor.getLocalName() == "xml");
    assert(cursor.getAttributes() == [cursor.Attribute("", "encoding", "utf-8")]);
    assert(cursor.getNamespaceDefinitions() == []);
    assert(cursor.hasChildren());
    
    cursor.enter();
        // <aaa xmlns:myns="something">
        assert(cursor.getKind() == XMLKind.ELEMENT_START);
        assert(cursor.getName() == "aaa");
        assert(cursor.getPrefix() == "");
        assert(cursor.getLocalName() == "aaa");
        assert(cursor.getAttributes() == []);
        assert(cursor.getNamespaceDefinitions() == [cursor.NamespaceDeclaration("myns", "something")]);
        assert(cursor.hasChildren());
        
        cursor.enter();
            // <myns:bbb myns:att='>'>
            assert(cursor.getKind() == XMLKind.ELEMENT_START);
            assert(cursor.getName() == "myns:bbb");
            assert(cursor.getPrefix() == "myns");
            assert(cursor.getLocalName() == "bbb");
            assert(cursor.getAttributes() == [cursor.Attribute("myns", "att", ">")]);
            assert(cursor.getNamespaceDefinitions() == []);
            assert(cursor.hasChildren());
            
            cursor.enter();
                // <!-- lol -->
                assert(cursor.getKind() == XMLKind.COMMENT);
                assert(cursor.getName() == "");
                assert(cursor.getPrefix() == "");
                assert(cursor.getLocalName() == "");
                assert(cursor.getAttributes() == []);
                assert(cursor.getNamespaceDefinitions() == []);
                assert(!cursor.hasChildren());
                
                assert(cursor.next());
                // Lots of Text!
                // On multiple lines!
                assert(cursor.getKind() == XMLKind.TEXT);
                assert(cursor.getName() == "");
                assert(cursor.getPrefix() == "");
                assert(cursor.getLocalName() == "");
                assert(cursor.getAttributes() == []);
                assert(cursor.getNamespaceDefinitions() == []);
                assert(!cursor.hasChildren());
                
                assert(!cursor.next());
            cursor.exit();
            
            // </myns:bbb>
            assert(cursor.getKind() == XMLKind.ELEMENT_END);
            assert(cursor.getName() == "myns:bbb");
            assert(cursor.getPrefix() == "myns");
            assert(cursor.getLocalName() == "bbb");
            assert(cursor.getAttributes() == []);
            assert(cursor.getNamespaceDefinitions() == []);
            assert(!cursor.hasChildren());
            
            assert(cursor.next());
            // <<![CDATA[ Ciaone! ]]>
            assert(cursor.getKind() == XMLKind.TEXT);
            assert(cursor.getName() == "");
            assert(cursor.getPrefix() == "");
            assert(cursor.getLocalName() == "");
            assert(cursor.getAttributes() == []);
            assert(cursor.getNamespaceDefinitions() == []);
            assert(!cursor.hasChildren());
            
            assert(cursor.next());
            // <ccc/>
            assert(cursor.getKind() == XMLKind.ELEMENT_EMPTY);
            assert(cursor.getName() == "ccc");
            assert(cursor.getPrefix() == "");
            assert(cursor.getLocalName() == "ccc");
            assert(cursor.getAttributes() == []);
            assert(cursor.getNamespaceDefinitions() == []);
            assert(!cursor.hasChildren());
            
            assert(!cursor.next());
        cursor.exit();
        
        // </aaa>
        assert(cursor.getKind() == XMLKind.ELEMENT_END);
        assert(cursor.getName() == "aaa");
        assert(cursor.getPrefix() == "");
        assert(cursor.getLocalName() == "aaa");
        assert(cursor.getAttributes() == []);
        assert(cursor.getNamespaceDefinitions() == []);
        assert(!cursor.hasChildren());
        
        assert(!cursor.next());
    cursor.exit();
    
    assert(cursor.documentEnd());
}
