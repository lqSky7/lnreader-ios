import Foundation

enum ReaderTTSJavaScript {
    // The paragraph class is an anchor for following, never a visual highlight.
    static let highlightStyle = """
    .tts-active { background: transparent; box-shadow: none; }
    ::highlight(tts-word) { background-color: rgba(250,45,72,0.48); color: inherit; }
    """

    static let mapping = #"""
    window.ttsIsAnnotation = function(node) {
        for (var element = node.nodeType === 1 ? node : node.parentElement; element; element = element.parentElement) {
            var type = element.getAttribute('epub:type') || '';
            if (/(?:^|\s)(?:noteref|footnote|endnote|pagebreak)(?:\s|$)/.test(type)) return true;
            if (element.matches('[role="doc-noteref"],[role="doc-footnote"],[role="doc-endnote"],[role="doc-pagebreak"]')) return true;
            if (element.tagName === 'A' && /#(?:fn|footnote|endnote|note|ref)[-_:\d]/i.test(element.getAttribute('href') || '')) return true;
            if (element.tagName === 'SUP' && /^\[?\d{1,4}\]?$/.test(element.textContent.trim()) && element.querySelector('a[href]')) return true;
        }
        return false;
    };
    window.ttsTextMap = function(element) {
        var walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
            acceptNode: function(node) {
                if (node.nodeType === 1) return node.tagName === 'BR' ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                var parent = node.parentElement;
                if (window.ttsIsAnnotation(node)) return NodeFilter.FILTER_REJECT;
                if (parent && parent.closest('script,style,[role="doc-noteref"],[role="doc-pagebreak"],a[href^="#fn"],#lnw-comments-section')) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        var text = '', map = [], node, pending = null;
        while ((node = walker.nextNode())) {
            if (node.nodeType === 1) { if (text.length && !pending) pending = map[map.length - 1]; continue; }
            for (var i = 0; i < node.nodeValue.length; i++) {
                var character = node.nodeValue[i];
                if (/\s/.test(character)) {
                    if (text.length && !pending) pending = {node: node, offset: i};
                } else {
                    if (pending) { text += ' '; map.push(pending); pending = null; }
                    text += character; map.push({node: node, offset: i});
                }
            }
        }
        return {text: text, map: map};
    };
    window.ttsParagraphNodes = function() {
        var nodes = Array.from(document.querySelectorAll('p,h1,h2,h3,h4,h5,h6,li')).filter(function(node) {
            return !window.ttsIsAnnotation(node) && !node.closest('#lnw-comments-section,nav,script,style,[role="doc-footnote"]') &&
                !(node.tagName === 'LI' && node.querySelector('p,li'));
        });
        if (nodes.length) return nodes;
        var root = document.querySelector('article,main,#chapter-content,.reader-content') || document.body;
        var leaves = Array.from(root.querySelectorAll('div,section')).filter(function(node) {
            return !node.querySelector('div,section') && !node.closest('nav,script,style,#lnw-comments-section');
        });
        return leaves.length ? leaves : [root];
    };
    window.ttsExtractBlocks = function() {
        var blocks = [];
        window.ttsParagraphNodes().forEach(function(node) {
            var text = window.ttsTextMap(node).text;
            node.setAttribute('data-tts-index', text ? String(blocks.length) : '-1');
            if (text) blocks.push(text);
        });
        return blocks;
    };
    """#

    static let interaction = #"""
    window.__ttsFollowing = true;
    window.__ttsSpeechMode = false;
    window.__ttsControlsVisible = true;
    window.__ttsWord = null;
    window.ttsSetFollowing = function(value) {
        if (window.__ttsFollowing === value) return;
        window.__ttsFollowing = value;
        window.webkit.messageHandlers.ttsFollowChanged.postMessage(value);
    };
    window.clearTTSActive = function() {
        window.__ttsWord = null;
        if (window.CSS && CSS.highlights) CSS.highlights.delete('tts-word');
        document.querySelectorAll('.tts-active').forEach(function(node) { node.classList.remove('tts-active'); });
        var dot = document.getElementById('tts-dot');
        if (dot) dot.style.opacity = 0;
    };
    window.setTTSSpeechMode = function(value) {
        window.__ttsSpeechMode = value;
        document.body.classList.toggle('tts-speech-mode', value);
        if (!value) window.clearTTSActive();
    };
    window.setTTSControlsVisible = function(value) {
        window.__ttsControlsVisible = value;
        document.body.style.setProperty('--tts-top', value ? '120px' : '24px');
        document.body.style.setProperty('--tts-bottom', value ? '260px' : '32px');
        if (window.__ttsSpeechMode && window.__ttsWord) window.setTTSActiveWord(window.__ttsWord);
    };
    window.ttsRange = function(word) {
        var target = document.querySelector('[data-tts-index="' + word.paragraphIndex + '"]');
        if (!target) return null;
        var mapped = window.ttsTextMap(target);
        var start = mapped.map[word.sourceStart], end = mapped.map[word.sourceEnd - 1];
        if (!start || !end) return null;
        var range = document.createRange();
        range.setStart(start.node, start.offset); range.setEnd(end.node, end.offset + 1);
        return {range: range, target: target};
    };
    window.setTTSActiveWord = function(word) {
        if (!window.__ttsSpeechMode || !word) { window.clearTTSActive(); return; }
        var mapped = window.ttsRange(word);
        if (!mapped) { window.clearTTSActive(); return; }
        window.__ttsWord = word;
        var active = document.querySelector('.tts-active');
        if (active && active !== mapped.target) active.classList.remove('tts-active');
        mapped.target.classList.add('tts-active');
        if (window.CSS && CSS.highlights && window.Highlight) CSS.highlights.set('tts-word', new Highlight(mapped.range));
        var rect = mapped.range.getBoundingClientRect();
        var topInset = window.__ttsControlsVisible ? 120 : 32;
        var bottomInset = window.__ttsSpeechMode ? (window.__ttsControlsVisible ? 260 : 32) : 120;
        if (window.__ttsFollowing && (rect.top < topInset || rect.bottom > window.innerHeight - bottomInset)) {
            var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
            window.scrollBy({top: rect.top - Math.max(topInset, (window.innerHeight - bottomInset) * 0.42), behavior: reduceMotion ? 'instant' : 'smooth'});
        }
    };
    window.resumeTTSFollow = function() {
        window.ttsSetFollowing(true);
        if (window.__ttsWord) window.setTTSActiveWord(window.__ttsWord);
    };
    window.addEventListener('touchmove', function() { if (window.__ttsSpeechMode) window.ttsSetFollowing(false); }, {passive: true});
    window.addEventListener('wheel', function() { if (window.__ttsSpeechMode) window.ttsSetFollowing(false); }, {passive: true});
    document.addEventListener('selectionchange', function() {
        if (window.__ttsSpeechMode && window.getSelection().toString().trim()) window.ttsSetFollowing(false);
    });
    window.ttsPositionAt = function(x, y) {
        var range = document.caretRangeFromPoint ? document.caretRangeFromPoint(x, y) : null;
        if (!range && document.caretPositionFromPoint) {
            var caret = document.caretPositionFromPoint(x, y);
            if (caret) { range = document.createRange(); range.setStart(caret.offsetNode, caret.offset); }
        }
        if (!range) return null;
        var element = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
        var paragraph = element.closest('[data-tts-index]');
        if (!paragraph) return null;
        var mapped = window.ttsTextMap(paragraph);
        var offset = mapped.map.findIndex(function(item) { return item.node === range.startContainer && item.offset >= range.startOffset; });
        if (offset < 0) offset = mapped.map.length - 1;
        var segments = new Intl.Segmenter('en', {granularity: 'word'}).segment(mapped.text);
        for (var segment of segments) {
            if (segment.isWordLike && segment.index <= offset && offset < segment.index + segment.segment.length) {
                return {paragraphIndex: Number(paragraph.getAttribute('data-tts-index')), offset: segment.index};
            }
        }
        return null;
    };
    window.addEventListener('dblclick', function(event) {
        if (!window.__ttsSpeechMode || event.target.closest('a,button')) return;
        event.preventDefault(); clearTimeout(window.__ttsSingleTap);
        var position = window.ttsPositionAt(event.clientX, event.clientY);
        if (position && position.paragraphIndex >= 0) {
            window.getSelection().removeAllRanges();
            window.webkit.messageHandlers.ttsWordTap.postMessage(position);
        }
    });
    document.addEventListener('contextmenu', function(event) {
        if (!window.__ttsSpeechMode) return;
        // Keep native long-press selection; following remains suspended until explicitly resumed.
        window.ttsSetFollowing(false);
    });
        // Gestures management using PointerEvents
        var startX = 0;
        var startY = 0;
        var startTime = 0;

        window.addEventListener("pointerdown", function(e) {
            if (!e.isPrimary) return;
            if (e.target.tagName === 'A' || e.target.closest('a') || e.target.tagName === 'BUTTON') return;

            startX = e.clientX;
            startY = e.clientY;
            startTime = Date.now();
        });

        window.addEventListener("pointerup", function(e) {
            if (!e.isPrimary) return;
            if (e.target.tagName === 'A' || e.target.closest('a') || e.target.tagName === 'BUTTON') return;

            var diffX = e.clientX - startX;
            var diffY = e.clientY - startY;
            var elapsed = Date.now() - startTime;

            // Check if there is active selection
            var selection = window.getSelection().toString();
            if (selection && selection.trim().length > 0) {
                return;
            }

            // Tap detection
            if (Math.abs(diffX) < 8 && Math.abs(diffY) < 8 && elapsed < 300) {
                clearTimeout(window.__ttsSingleTap);
                window.__ttsSingleTap = setTimeout(function() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.toggleControls) {
                        window.webkit.messageHandlers.toggleControls.postMessage("");
                    }
                }, window.__ttsSpeechMode ? 320 : 0);
            }
        });

    """#
}
