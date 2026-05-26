import Foundation

struct PluginShims {
    static let jsCode = #"""
        (function(global, pluginID) {

            // Uint8Array polyfill — JSC on modern iOS has it natively; this guard is a safety net.
            if (typeof Uint8Array === 'undefined') {
                global.Uint8Array = function(arg) {
                    var arr;
                    if (typeof arg === 'number') {
                        arr = new Array(arg);
                        for (var i = 0; i < arg; i++) arr[i] = 0;
                    } else if (Array.isArray(arg)) {
                        arr = arg.map(function(v) { return (v & 0xFF) >>> 0; });
                    } else {
                        arr = [];
                    }
                    arr.buffer = { byteLength: arr.length };
                    return arr;
                };
            }

            // John Resig's HTML Parser Regexes (built with RegExp to catch and log any parser exceptions)
            var startTag, endTag, attr;
            try {
                startTag = new RegExp("^<([-A-Za-z0-9_]+)((?:\\s+[-A-Za-z0-9_@:-]+(?:\\s*=\\s*(?:(?:\"[^\"]*\")|(?:'[^']*')|[^>\\s]+))?)*)\\s*(/?)>");
            } catch (e) {
                console.error("Failed to compile startTag regex: " + e);
            }
            try {
                endTag = new RegExp("^</([-A-Za-z0-9_]+)[^>]*>");
            } catch (e) {
                console.error("Failed to compile endTag regex: " + e);
            }
            try {
                attr = new RegExp("([-A-Za-z0-9_@:-]+)(?:\\s*=\\s*(?:(?:\"((?:\\\\.|[^\"])*)\")|(?:'((?:\\\\.|[^'])*)')|([^>\\s]+)))?", "g");
            } catch (e) {
                console.error("Failed to compile attr regex: " + e);
            }

            var empty = makeMap("area,base,basefont,br,col,frame,hr,img,input,isindex,link,meta,param,embed");
            var block = makeMap("address,applet,blockquote,button,center,dd,del,dir,div,dl,dt,fieldset,form,frameset,hr,iframe,ins,isindex,li,map,menu,noframes,noscript,object,ol,p,pre,script,table,tbody,td,tfoot,th,thead,tr,ul");
            var inline = makeMap("a,abbr,acronym,applet,b,basefont,bdo,big,br,button,cite,code,del,dfn,em,font,i,iframe,img,input,ins,kbd,label,map,object,q,s,samp,script,select,small,span,strike,strong,sub,sup,textarea,tt,u,var");
            var closeSelf = makeMap("colgroup,dd,dt,li,options,p,td,tfoot,th,thead,tr");
            var special = makeMap("script,style");

            function makeMap(str) {
                var obj = {}, items = str.split(",");
                for (var i = 0; i < items.length; i++) obj[items[i]] = true;
                return obj;
            }

            function parseHTML(html, handler) {
                var index, chars, match, stack = [], last = html;
                stack.last = function() { return this[this.length - 1]; };

                while (html) {
                    chars = true;

                    if (!stack.last() || !special[stack.last()]) {
                        if (html.indexOf("<!--") == 0) {
                            index = html.indexOf("-->");
                            if (index >= 0) {
                                if (handler.comment) handler.comment(html.substring(4, index));
                                html = html.substring(index + 3);
                                chars = false;
                            }
                        } else if (html.indexOf("</") == 0) {
                            match = html.match(endTag);
                            if (match) {
                                html = html.substring(match[0].length);
                                match[0].replace(endTag, parseEndTag);
                                chars = false;
                            }
                        } else if (html.indexOf("<") == 0) {
                            match = html.match(startTag);
                            if (match) {
                                html = html.substring(match[0].length);
                                match[0].replace(startTag, parseStartTag);
                                chars = false;
                            }
                        }

                        if (chars) {
                            index = html.indexOf("<");
                            var text = index < 0 ? html : html.substring(0, index);
                            html = index < 0 ? "" : html.substring(index);
                            if (handler.chars) handler.chars(text);
                        }
                    } else {
                        var reSpecial = new RegExp("([\\s\\S]*?)</" + stack.last() + "[^>]*>", "i");
                        html = html.replace(reSpecial, function(all, text) {
                            var reCommentCdata = new RegExp("<!--([\\s\\S]*?)-->|<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", "g");
                            text = text.replace(reCommentCdata, "$1$2");
                            if (handler.chars) handler.chars(text);
                            return "";
                        });
                        parseEndTag("", stack.last());
                    }

                    if (html == last) {
                        if (handler.chars) handler.chars(html.charAt(0));
                        html = html.substring(1);
                    }
                    last = html;
                }

                parseEndTag();

                function parseStartTag(tag, tagName, rest, unary) {
                    tagName = tagName.toLowerCase();
                    /* Removed block-closes-inline constraint to support HTML5 standard (e.g. <a> wrapping <div>) */
                    if (closeSelf[tagName] && stack.last() == tagName) {
                        parseEndTag("", tagName);
                    }
                    unary = empty[tagName] || !!unary;
                    if (!unary) stack.push(tagName);
                    if (handler.start) {
                        var attrs = {};
                        rest.replace(attr, function(match, name, doubleQuote, singleQuote, unquoted) {
                            var value = doubleQuote !== undefined ? doubleQuote :
                                        (singleQuote !== undefined ? singleQuote :
                                        (unquoted !== undefined ? unquoted : ""));
                            attrs[name.toLowerCase()] = value;
                        });
                        handler.start(tagName, attrs, unary);
                    }
                }

                function parseEndTag(tag, tagName) {
                    var pos;
                    if (!tagName) pos = 0;
                    else {
                        for (pos = stack.length - 1; pos >= 0; pos--) {
                            if (stack[pos] == tagName.toLowerCase()) break;
                        }
                    }
                    if (pos >= 0) {
                        for (var i = stack.length - 1; i >= pos; i--) {
                            if (handler.end) handler.end(stack[i]);
                        }
                        stack.length = pos;
                    }
                }
            }

            // Node classes
            function ElementNode(name, attribs, parent) {
                this.name = name;
                this.tagName = name;
                this.attribs = attribs || {};
                this.parent = parent || null;
                this.children = [];
                this.nodeType = 1;
            }

            function TextNode(text, parent) {
                this.data = text;
                this.parent = parent || null;
                this.nodeType = 3;
            }

            function buildDOM(html) {
                const root = new ElementNode("root", {}, null);
                let current = root;
                parseHTML(html, {
                    start: function(tagName, attrs, unary) {
                        const node = new ElementNode(tagName, attrs, current);
                        current.children.push(node);
                        if (!unary) {
                            current = node;
                        }
                    },
                    end: function(tagName) {
                        if (current !== root) {
                            current = current.parent;
                        }
                    },
                    chars: function(text) {
                        const node = new TextNode(text, current);
                        current.children.push(node);
                    }
                });
                return root;
            }

            function getNodeText(node) {
                if (node.nodeType === 3) return node.data;
                if (node.nodeType === 1) {
                    return node.children.map(getNodeText).join("");
                }
                return "";
            }

            // CSS Matcher
            function matchPart(node, part) {
                if (node.nodeType !== 1) return false;

                let containsText = null;
                try {
                    const containsMatch = part.match(new RegExp(":contains\\((?:\"([^\"]*)\"|'([^']*)'|([^)]*))\\)"));
                    if (containsMatch) {
                        containsText = containsMatch[1] || containsMatch[2] || containsMatch[3];
                        part = part.replace(new RegExp(":contains\\(.*?\\)", "g"), "");
                    }
                } catch (e) {
                    console.error("Failed in matchPart containsMatch: " + e);
                }

                try {
                    const match = part.match(new RegExp("^([A-Za-z0-9_*-]+)?((?:\\.[A-Za-z0-9_-]+)*)(?:#([A-Za-z0-9_-]+))?$"));
                    if (!match) return false;

                    const tagName = match[1];
                    const classes = match[2] ? match[2].split(".").filter(Boolean) : [];
                    const id = match[3];

                    if (tagName && tagName !== "*" && node.name !== tagName.toLowerCase()) {
                        return false;
                    }

                    if (id && node.attribs.id !== id) {
                        return false;
                    }

                    if (classes.length > 0) {
                        const nodeClassStr = node.attribs["class"] || "";
                        const nodeClasses = nodeClassStr.split(new RegExp("\\s+")).filter(Boolean);
                        for (var i = 0; i < classes.length; i++) {
                            var cls = classes[i];
                            if (nodeClasses.indexOf(cls) === -1) return false;
                        }
                    }
                } catch (e) {
                    console.error("Failed in matchPart classes match: " + e);
                }

                if (containsText) {
                    const text = getNodeText(node);
                    if (text.indexOf(containsText) === -1) return false;
                }

                return true;
            }

            function parseSelectorGroup(selector) {
                var tokens = [];
                try {
                    tokens = selector.replace(new RegExp("\\s*>\\s*", "g"), " > ").split(new RegExp("\\s+")).filter(Boolean);
                } catch (e) {
                    console.error("Failed in parseSelectorGroup replace: " + e);
                }
                const parts = [];
                let relation = "descendant";
                for (var i = 0; i < tokens.length; i++) {
                    var token = tokens[i];
                    if (token === ">") {
                        relation = "child";
                    } else {
                        parts.push({ selector: token, relation: relation });
                        relation = "descendant";
                    }
                }
                return parts;
            }

            function getAllDescendants(node, list) {
                for (var i = 0; i < node.children.length; i++) {
                    var child = node.children[i];
                    if (child.nodeType === 1) {
                        list.push(child);
                        getAllDescendants(child, list);
                    }
                }
            }

            function findMatches(root, parts) {
                if (parts.length === 0) return [];
                let currentSet = [root];
                for (let i = 0; i < parts.length; i++) {
                    const part = parts[i];
                    let nextSet = [];
                    for (var j = 0; j < currentSet.length; j++) {
                        var node = currentSet[j];
                        const candidates = [];
                        if (part.relation === "child") {
                            for (var k = 0; k < node.children.length; k++) {
                                var child = node.children[k];
                                if (child.nodeType === 1) candidates.push(child);
                            }
                        } else {
                            getAllDescendants(node, candidates);
                        }

                        for (var k = 0; k < candidates.length; k++) {
                            var cand = candidates[k];
                            if (matchPart(cand, part.selector)) {
                                if (nextSet.indexOf(cand) === -1) {
                                    nextSet.push(cand);
                                }
                            }
                        }
                    }
                    currentSet = nextSet;
                    if (currentSet.length === 0) break;
                }
                return currentSet;
            }

            function selectNodes(root, selector) {
                const groups = selector.split(",").map(function(s) { return s.trim(); }).filter(Boolean);
                let results = [];
                for (var i = 0; i < groups.length; i++) {
                    var group = groups[i];
                    const parsed = parseSelectorGroup(group);
                    const matches = findMatches(root, parsed);
                    for (var j = 0; j < matches.length; j++) {
                        var m = matches[j];
                        if (results.indexOf(m) === -1) {
                            results.push(m);
                        }
                    }
                }
                return results;
            }

            function getWrapperHTML(nodes) {
                let html = "";
                for (var i = 0; i < nodes.length; i++) {
                    var node = nodes[i];
                    if (node.nodeType === 3) {
                        html += escapeHTML(node.data);
                    } else if (node.nodeType === 1) {
                        let attrStr = "";
                        for (const key in node.attribs) {
                            attrStr += " " + key + "=\"" + escapeHTML(node.attribs[key]) + "\"";
                        }
                        const tagName = node.name;
                        if (empty[tagName]) {
                            html += "<" + tagName + attrStr + " />";
                        } else {
                            html += "<" + tagName + attrStr + ">" + getWrapperHTML(node.children) + "</" + tagName + ">";
                        }
                    }
                }
                return html;
            }

            function escapeHTML(str) {
                if (typeof str !== "string") return "";
                return str.replace(/&/g, "&amp;")
                          .replace(/</g, "&lt;")
                          .replace(/>/g, "&gt;")
                          .replace(/"/g, "&quot;")
                          .replace(/'/g, "&#39;");
            }

            function createWrapper(nodes, select) {
                const wrapper = {
                    isCheerioWrapper: true,
                    length: nodes.length,
                    toArray: function() {
                        return nodes;
                    },
                    get: function(index) {
                        if (index === undefined) return nodes;
                        return nodes[index < 0 ? nodes.length + index : index];
                    },
                    eq: function(index) {
                        const idx = index < 0 ? nodes.length + index : index;
                        return select(nodes[idx] ? [nodes[idx]] : []);
                    },
                    first: function() {
                        return select(nodes[0] ? [nodes[0]] : []);
                    },
                    last: function() {
                        return select(nodes[nodes.length - 1] ? [nodes[nodes.length - 1]] : []);
                    },
                    text: function(newText) {
                        if (newText !== undefined) {
                            for (var i = 0; i < nodes.length; i++) {
                                var node = nodes[i];
                                if (node.nodeType === 1) {
                                    node.children = [newText === "" ? "" : new TextNode(String(newText), node)];
                                }
                            }
                            return this;
                        }
                        return nodes.map(getNodeText).join("");
                    },
                    html: function(newHtml) {
                        if (newHtml !== undefined) {
                            for (var i = 0; i < nodes.length; i++) {
                                var node = nodes[i];
                                if (node.nodeType === 1) {
                                    const tempRoot = buildDOM(newHtml);
                                    for (var j = 0; j < tempRoot.children.length; j++) {
                                        tempRoot.children[j].parent = node;
                                    }
                                    node.children = tempRoot.children;
                                }
                            }
                            return this;
                        }
                        if (nodes[0] && nodes[0].nodeType === 1) {
                            return getWrapperHTML(nodes[0].children);
                        }
                        return "";
                    },
                    attr: function(name, value) {
                        if (value !== undefined) {
                            for (var i = 0; i < nodes.length; i++) {
                                var node = nodes[i];
                                if (node.nodeType === 1) {
                                    node.attribs[name.toLowerCase()] = String(value);
                                }
                            }
                            return this;
                        }
                        if (nodes[0] && nodes[0].nodeType === 1) {
                            return nodes[0].attribs[name.toLowerCase()];
                        }
                        return undefined;
                    },
                    val: function(value) {
                        return this.attr("value", value);
                    },
                    remove: function() {
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            if (node.parent) {
                                const idx = node.parent.children.indexOf(node);
                                if (idx !== -1) {
                                    node.parent.children.splice(idx, 1);
                                }
                            }
                        }
                        return this;
                    },
                    find: function(selector) {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            const subMatches = selectNodes(node, selector);
                            for (var j = 0; j < subMatches.length; j++) {
                                var m = subMatches[j];
                                if (matched.indexOf(m) === -1) {
                                    matched.push(m);
                                }
                            }
                        }
                        const w = select(matched);
                        w.prevObject = wrapper;
                        return w;
                    },
                    parent: function() {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            if (node.parent && node.parent.name !== "root") {
                                if (matched.indexOf(node.parent) === -1) {
                                    matched.push(node.parent);
                                }
                            }
                        }
                        return select(matched);
                    },
                    children: function(selector) {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            for (var j = 0; j < node.children.length; j++) {
                                var child = node.children[j];
                                if (child.nodeType === 1) {
                                    if (!selector || matchPart(child, selector)) {
                                        matched.push(child);
                                    }
                                }
                            }
                        }
                        return select(matched);
                    },
                    contents: function() {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            for (var j = 0; j < node.children.length; j++) {
                                matched.push(node.children[j]);
                            }
                        }
                        return select(matched);
                    },
                    filter: function(fn) {
                        let matched = [];
                        if (typeof fn === "string") {
                            matched = nodes.filter(function(node) { return matchPart(node, fn); });
                        } else if (typeof fn === "function") {
                            matched = nodes.filter(function(node, index) { return fn.call(node, index, node); });
                        }
                        return select(matched);
                    },
                    each: function(fn) {
                        for (let i = 0; i < nodes.length; i++) {
                            fn.call(nodes[i], i, nodes[i]);
                        }
                        return this;
                    },
                    map: function(fn) {
                        const mapped = [];
                        for (let i = 0; i < nodes.length; i++) {
                            mapped.push(fn.call(nodes[i], i, nodes[i]));
                        }
                        return select(mapped);
                    },
                    addBack: function() {
                        return select(nodes.concat(wrapper.prevObject ? wrapper.prevObject.toArray() : []));
                    },
                    next: function() {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            if (node.parent) {
                                const idx = node.parent.children.indexOf(node);
                                if (idx !== -1) {
                                    for (let k = idx + 1; k < node.parent.children.length; k++) {
                                        const sib = node.parent.children[k];
                                        if (sib.nodeType === 1) {
                                            matched.push(sib);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        return select(matched);
                    },
                    prev: function() {
                        let matched = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            if (node.parent) {
                                const idx = node.parent.children.indexOf(node);
                                if (idx !== -1) {
                                    for (let k = idx - 1; k >= 0; k--) {
                                        const sib = node.parent.children[k];
                                        if (sib.nodeType === 1) {
                                            matched.push(sib);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        return select(matched);
                    }
                };

                for (let i = 0; i < nodes.length; i++) {
                    wrapper[i] = nodes[i];
                }

                return wrapper;
            }

            const cheerio = {
                load: function(html) {
                    const root = buildDOM(html);
                    function select(selectorOrNodes) {
                        let nodes = [];
                        if (typeof selectorOrNodes === "string") {
                            nodes = selectNodes(root, selectorOrNodes);
                        } else if (Array.isArray(selectorOrNodes)) {
                            nodes = selectorOrNodes;
                        } else if (selectorOrNodes && selectorOrNodes.nodeType) {
                            nodes = [selectorOrNodes];
                        } else if (selectorOrNodes && selectorOrNodes.isCheerioWrapper) {
                            return selectorOrNodes;
                        }
                        return createWrapper(nodes, select);
                    }
                    select.html = function() {
                        return getWrapperHTML(root.children);
                    };
                    return select;
                }
            };

            // htmlparser2
            const htmlparser2 = {
                Parser: function(handler) {
                    this.handler = handler;
                    this.buffer = "";
                    this.write = function(data) {
                        this.buffer += data;
                    };
                    this.end = function() {
                        const self = this;
                        parseHTML(this.buffer, {
                            start: function(tagName, attrs, unary) {
                                if (self.handler.onopentagname) {
                                    self.handler.onopentagname(tagName);
                                }
                                if (self.handler.onattribute) {
                                    for (const key in attrs) {
                                        self.handler.onattribute(key, attrs[key]);
                                    }
                                }
                                if (self.handler.onopentag) {
                                    self.handler.onopentag(tagName, attrs);
                                }
                            },
                            end: function(tagName) {
                                if (self.handler.onclosetag) {
                                    self.handler.onclosetag(tagName);
                                }
                            },
                            chars: function(text) {
                                if (self.handler.ontext) {
                                    self.handler.ontext(text);
                                }
                            }
                        });
                    };
                    this.isVoidElement = function(name) {
                        return empty[name.toLowerCase()] === true;
                    };
                }
            };

            // dayjs
            function dayjs(val) {
                let date = val ? new Date(val) : new Date();
                return {
                    subtract(amount, unit) {
                        let newDate = new Date(date.getTime());
                        if (unit.startsWith("second")) newDate.setSeconds(newDate.getSeconds() - amount);
                        else if (unit.startsWith("minute")) newDate.setMinutes(newDate.getMinutes() - amount);
                        else if (unit.startsWith("hour")) newDate.setHours(newDate.getHours() - amount);
                        else if (unit.startsWith("day")) newDate.setDate(newDate.getDate() - amount);
                        else if (unit.startsWith("week")) newDate.setDate(newDate.getDate() - amount * 7);
                        else if (unit.startsWith("month")) newDate.setMonth(newDate.getMonth() - amount);
                        else if (unit.startsWith("year")) newDate.setFullYear(newDate.getFullYear() - amount);
                        return dayjs(newDate);
                    },
                    format(fmt) {
                        if (isNaN(date.getTime())) return "Invalid Date";
                        if (fmt === "LL") {
                            return date.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" });
                        }
                        return date.toISOString();
                    }
                };
            }
            dayjs.default = dayjs;

            // urlencode
            const urlencode = function(str) { return encodeURIComponent(str); };
            urlencode.encode = function(str) { return encodeURIComponent(str); };
            urlencode.decode = function(str) { return decodeURIComponent(str); };

            // Storage shims
            class Storage {
                constructor(pluginId) {
                    this.pluginId = pluginId;
                }
                set(key, value, expires) {
                    const item = {
                        created: new Date(),
                        value: value,
                        expires: expires instanceof Date ? expires.getTime() : expires
                    };
                    _nativeStoreSet(this.pluginId + "_DB_" + key, JSON.stringify(item));
                }
                get(key, raw) {
                    const storedItem = _nativeStoreGet(this.pluginId + "_DB_" + key);
                    if (storedItem) {
                        const item = JSON.parse(storedItem);
                        if (item.expires) {
                            if (Date.now() > item.expires) {
                                this.delete(key);
                                return undefined;
                            }
                        }
                        return raw ? item : item.value;
                    }
                    return undefined;
                }
                delete(key) {
                    _nativeStoreRemove(this.pluginId + "_DB_" + key);
                }
                clearAll() {
                    const keys = this.getAllKeys();
                    for (var i = 0; i < keys.length; i++) {
                        this.delete(keys[i]);
                    }
                }
                getAllKeys() {
                    const prefix = this.pluginId + "_DB_";
                    const allKeys = _nativeStoreGetAllKeys();
                    return allKeys.filter(function(k) { return k.indexOf(prefix) === 0; }).map(function(k) { return k.substring(prefix.length); });
                }
            }

            class LocalStorage {
                constructor(pluginId) {
                    this.pluginId = pluginId;
                }
                get() {
                    const data = _nativeStoreGet(this.pluginId + "_LocalStorage");
                    return data ? JSON.parse(data) : undefined;
                }
            }

            class SessionStorage {
                constructor(pluginId) {
                    this.pluginId = pluginId;
                }
                get() {
                    const data = _nativeStoreGet(this.pluginId + "_SessionStorage");
                    return data ? JSON.parse(data) : undefined;
                }
            }

            // UTF-8 encoding / decoding utilities
            // Full implementation handles BMP characters and surrogate pairs for astral code points.
            const utf8ToBytes = function(str) {
                var bytes = [];
                for (var i = 0; i < str.length; i++) {
                    var code = str.charCodeAt(i);
                    // Handle surrogate pairs (astral characters above U+FFFF)
                    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
                        var high = code;
                        var low = str.charCodeAt(i + 1);
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            code = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
                            i++;
                        }
                    }
                    if (code < 0x80) {
                        bytes.push(code);
                    } else if (code < 0x800) {
                        bytes.push(0xC0 | (code >> 6));
                        bytes.push(0x80 | (code & 0x3F));
                    } else if (code < 0x10000) {
                        bytes.push(0xE0 | (code >> 12));
                        bytes.push(0x80 | ((code >> 6) & 0x3F));
                        bytes.push(0x80 | (code & 0x3F));
                    } else {
                        bytes.push(0xF0 | (code >> 18));
                        bytes.push(0x80 | ((code >> 12) & 0x3F));
                        bytes.push(0x80 | ((code >> 6) & 0x3F));
                        bytes.push(0x80 | (code & 0x3F));
                    }
                }
                return bytes;
            };

            const bytesToUtf8 = function(bytes) {
                var str = '';
                var i = 0;
                while (i < bytes.length) {
                    var b = bytes[i] & 0xFF;
                    var code;
                    if (b < 0x80) {
                        code = b;
                        i += 1;
                    } else if ((b & 0xE0) === 0xC0) {
                        code = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
                        i += 2;
                    } else if ((b & 0xF0) === 0xE0) {
                        code = ((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
                        i += 3;
                    } else {
                        code = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
                        i += 4;
                    }
                    if (code > 0xFFFF) {
                        // Encode as surrogate pair
                        code -= 0x10000;
                        str += String.fromCharCode(0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF));
                    } else {
                        str += String.fromCharCode(code);
                    }
                }
                return str;
            };

            // AES-GCM bridge — delegates to the native CryptoKit implementation
            const gcm = function(key, nonce, aad) {
                return _nativeGCMCreate(key, nonce, aad !== undefined ? aad : null);
            };

            // URLSearchParams
            class URLSearchParams {
                constructor(init) {
                    this.params = [];
                    if (typeof init === "string") {
                        var pairs = init.split("&");
                        for (var i = 0; i < pairs.length; i++) {
                            var pair = pairs[i].split("=");
                            this.params.push([
                                decodeURIComponent(pair[0] || ""),
                                decodeURIComponent(pair[1] || "")
                            ]);
                        }
                    } else if (init && typeof init === "object") {
                        for (const key in init) {
                            this.params.push([key, init[key]]);
                        }
                    }
                }
                append(key, value) {
                    this.params.push([key, String(value)]);
                }
                set(key, value) {
                    this.delete(key);
                    this.append(key, value);
                }
                delete(key) {
                    this.params = this.params.filter(function(p) { return p[0] !== key; });
                }
                get(key) {
                    const found = this.params.find(function(p) { return p[0] === key; });
                    return found ? found[1] : null;
                }
                toString() {
                    return this.params.map(function(p) {
                        return encodeURIComponent(p[0]) + "=" + encodeURIComponent(p[1]);
                    }).join("&");
                }
            }
            global.URLSearchParams = URLSearchParams;

            // FormData
            class FormData {
                constructor() {
                    this.fields = [];
                }
                append(key, value) {
                    this.fields.push([key, value]);
                }
                toString() {
                    return this.fields.map(function(f) {
                        return encodeURIComponent(f[0]) + "=" + encodeURIComponent(f[1]);
                    }).join("&");
                }
            }
            global.FormData = FormData;

            // Headers
            class Headers {
                constructor(init) {
                    this.map = {};
                    if (init) {
                        for (const key in init) {
                            this.map[key.toLowerCase()] = init[key];
                        }
                    }
                }
                append(key, value) {
                    this.map[key.toLowerCase()] = value;
                }
                set(key, value) {
                    this.map[key.toLowerCase()] = value;
                }
                get(key) {
                    return this.map[key.toLowerCase()] || null;
                }
                has(key) {
                    return key.toLowerCase() in this.map;
                }
            }
            global.Headers = Headers;

            // setTimeout / clearTimeout polyfills using native bridges
            global.setTimeout = function(callback, delay) {
                return _nativeSetTimeout(callback, delay);
            };
            global.clearTimeout = function(timerID) {
                _nativeClearTimeout(timerID);
            };

            // @libs/novelStatus
            const NovelStatus = {
                Unknown: 'Unknown',
                Ongoing: 'Ongoing',
                Completed: 'Completed',
                Licensed: 'Licensed',
                PublishingFinished: 'Publishing Finished',
                Cancelled: 'Cancelled',
                OnHiatus: 'On Hiatus'
            };

            // @libs/defaultCover
            const defaultCover = 'https://github.com/lnreader/lnreader-plugins/blob/master/public/static/coverNotAvailable.webp?raw=true';

            // @libs/isAbsoluteUrl
            const isUrlAbsolute = function(url) {
                if (url) {
                    if (url.indexOf('//') === 0) return true;
                    if (url.indexOf('://') === -1) return false;
                    if (url.indexOf('.') === -1) return false;
                    if (url.indexOf('/') === -1) return false;
                    if (url.indexOf(':') > url.indexOf('/')) return false;
                    if (url.indexOf('://') < url.indexOf('.')) return true;
                }
                return false;
            };

            // @libs/filterInputs
            const FilterTypes = {
                TextInput: 'Text',
                Picker: 'Picker',
                CheckboxGroup: 'Checkbox',
                Switch: 'Switch',
                ExcludableCheckboxGroup: 'XCheckbox'
            };

            // @libs/fetch (wrapped to handle FormData & Content-Type conversion)
            var originalFetch = global.fetch;
            global.fetch = function(url, init) {
                if (init && init.body && init.body instanceof FormData) {
                    init.body = init.body.toString();
                    init.headers = init.headers || {};
                    var hasContentType = false;
                    for (const k in init.headers) {
                        if (k.toLowerCase() === 'content-type') {
                            hasContentType = true;
                            break;
                        }
                    }
                    if (!hasContentType) {
                        init.headers["Content-Type"] = "application/x-www-form-urlencoded";
                    }
                }
                return originalFetch(url, init);
            };

            const fetchApi = global.fetch;

            // fetchText — supports an optional encoding parameter for non-UTF-8 responses.
            // When encoding is a non-UTF-8 IANA charset name (e.g. "windows-1252", "gbk"),
            // delegates to the native _nativeFetchTextWithEncoding bridge for correct decoding.
            const fetchText = function(url, init, encoding) {
                if (encoding && encoding.toLowerCase() !== 'utf-8' && encoding.toLowerCase() !== 'utf8') {
                    return _nativeFetchTextWithEncoding(url, init || null, encoding);
                }
                return global.fetch(url, init).then(function(res) {
                    if (!res.ok) { throw new Error('HTTP ' + res.status); }
                    return res.text();
                });
            };

            // fetchProto — protobuf decoding is not yet supported on iOS.
            const fetchProto = function(protoInit, url, init) {
                return Promise.reject(new Error('fetchProto is not yet supported on iOS'));
            };

            // Module registry setup
            global.__modules = {
                'htmlparser2': htmlparser2,
                'cheerio': cheerio,
                'dayjs': dayjs,
                'urlencode': urlencode,
                '@libs/novelStatus': {
                    NovelStatus: NovelStatus,
                    Unknown: NovelStatus.Unknown,
                    Ongoing: NovelStatus.Ongoing,
                    Completed: NovelStatus.Completed,
                    Licensed: NovelStatus.Licensed,
                    PublishingFinished: NovelStatus.PublishingFinished,
                    Cancelled: NovelStatus.Cancelled,
                    OnHiatus: NovelStatus.OnHiatus
                },
                '@libs/defaultCover': { defaultCover: defaultCover },
                '@libs/isAbsoluteUrl': { isUrlAbsolute: isUrlAbsolute },
                '@libs/filterInputs': { FilterTypes: FilterTypes },
                '@libs/fetch': { fetchApi: fetchApi, fetchText: fetchText, fetchProto: fetchProto },
                '@libs/utils': { utf8ToBytes: utf8ToBytes, bytesToUtf8: bytesToUtf8 },
                '@libs/aes': { gcm: gcm }
            };

            // Require Polyfill
            global.require = function(moduleName) {
                if (moduleName === '@libs/storage') {
                    return {
                        storage: new Storage(pluginID),
                        localStorage: new LocalStorage(pluginID),
                        sessionStorage: new SessionStorage(pluginID)
                    };
                }
                if (global.__modules[moduleName]) {
                    return global.__modules[moduleName];
                }
                console.warn("require('" + moduleName + "') — returned empty stub");
                return {};
            };

            global.cheerio = cheerio;
            global.htmlparser2 = htmlparser2;
            global.dayjs = dayjs;
            global.urlencode = urlencode;
            global.NovelStatus = NovelStatus;
            global.defaultCover = defaultCover;
            global.isUrlAbsolute = isUrlAbsolute;
            global.FilterTypes = FilterTypes;
            global.utf8ToBytes = utf8ToBytes;
            global.bytesToUtf8 = bytesToUtf8;
            global.gcm = gcm;

            // URL Polyfill
            class URL {
                constructor(url, base) {
                    let resolved = url;
                    if (base && !url.includes("://") && !url.startsWith("//")) {
                        let b = base;
                        if (b.endsWith("/")) {
                            b = b.slice(0, -1);
                        }
                        if (url.startsWith("/")) {
                            resolved = b + url;
                        } else {
                            resolved = b + "/" + url;
                        }
                    } else if (url.startsWith("//")) {
                        resolved = "https:" + url;
                    }

                    this.href = resolved;

                    let path = resolved;
                    let protocolIdx = path.indexOf("://");
                    if (protocolIdx !== -1) {
                        path = path.substring(protocolIdx + 3);
                    }
                    let slashIdx = path.indexOf("/");
                    if (slashIdx !== -1) {
                        let qIdx = path.indexOf("?");
                        let hIdx = path.indexOf("#");
                        let endIdx = path.length;
                        if (qIdx !== -1) endIdx = Math.min(endIdx, qIdx);
                        if (hIdx !== -1) endIdx = Math.min(endIdx, hIdx);
                        this.pathname = path.substring(slashIdx, endIdx);
                    } else {
                        this.pathname = "/";
                    }
                }
            }
            global.URL = URL;

            if (typeof globalThis !== 'undefined') {
                globalThis.require = global.require;
                globalThis.cheerio = global.cheerio;
                globalThis.htmlparser2 = global.htmlparser2;
                globalThis.dayjs = global.dayjs;
                globalThis.urlencode = global.urlencode;
                globalThis.URLSearchParams = URLSearchParams;
                globalThis.FormData = FormData;
                globalThis.Headers = Headers;
                globalThis.URL = URL;
                globalThis.setTimeout = global.setTimeout;
                globalThis.clearTimeout = global.clearTimeout;
                globalThis.utf8ToBytes = utf8ToBytes;
                globalThis.bytesToUtf8 = bytesToUtf8;
                globalThis.gcm = gcm;
            }
        })(typeof globalThis !== 'undefined' ? globalThis : this, pluginID);
        """#
}
