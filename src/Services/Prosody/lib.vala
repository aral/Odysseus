/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2017).
*
* Oddysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Oddysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Oddysseus.  If not, see <http://www.gnu.org/licenses/>.
*/

/* Standard "tags" and "filters" to use in templates.
	Beware that these may differ subtly from Django's implementation. */
namespace Oddysseus.Templating.Std {
    public Gee.Map<Bytes, Variable> parse_params(WordIter args)
            throws SyntaxError {
		var parameters = ByteUtils.create_map<Variable>();
		var count = 0;
		foreach (var arg in args) {
			var parts = smart_split(arg, "=");
			var key = parts.next();
			var val = parts.next_value();
			parts.assert_end();

			if (val == null) {
			    val = key;
				key = ByteUtils.from_string("$%i".printf(count++));
			}

			parameters[key] = new Variable(val);
		}
		return parameters;
    }

	private class AutoescapeBuilder : TagBuilder, Object {
		public static Gee.Map<Bytes,Gee.Map<char,string>>? _modes;
		public static Gee.Map<Bytes,Gee.Map<char,string>> modes {
		    get {
		        if (_modes == null)
		            _modes = ByteUtils.create_map<Gee.Map<char,string>>();
	            return _modes;
            }
        }

		public Template? build(Parser parser, WordIter args) throws SyntaxError {
		    var mode = args.next();
			args.assert_end();
			if (!modes.has_key(mode)) throw new SyntaxError.INVALID_ARGS(
			        "Invalid {%% autoescape %%} mode: '%s'",
		            ByteUtils.to_string(mode));

			var prev = parser.escapes;
			parser.escapes = modes[mode];
			modes[ByteUtils.from_string("end")] = prev;
			return null;
		}
	}

	// Defines a function capable of recursion
	private class Block : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
		    var name = args.next();
		    args.assert_end();

			if (name[0] in "\"'".data || tag_lib.has_key(name) ||
					parser.local_tag_lib.has_key(name)) {
				throw new SyntaxError.INVALID_ARGS(
						"%s is an invalid tag name, either because " +
						"it starts with a quote or is already defined", name);
			}
			var macro = new Macro();
			parser.local_tag_lib[name] = macro;

			WordIter? endtoken;
			var body = parser.parse("endblock", out endtoken);
			if (endtoken == null) throw new SyntaxError.UNBALANCED_TAGS(
					"{%% block %s %%} must be closed with a {%% endblock %%} tag",
					ByteUtils.to_string(name));
			// Let the programmer add a note to the end tag, so don't check it.

			macro.body = body;
			return null;
		}
	}
	private class Macro : TagBuilder, Object {
		public Template body;
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
			return new BlockTag(this, parse_params(args));
		}
	}
	private class BlockTag : Template {
		// Indirect reference to body template in order to support recursion.
		private Macro macro;
		private Gee.Map<Bytes,Variable> args;
		public BlockTag(Macro m, Gee.Map<Bytes,Variable> arguments) {
			this.macro = m;
			this.args = arguments;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			yield macro.body.exec(new Data.Lazy(args, ctx), output);
		}
	}

	private class FilterBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
		    var filter_tail = args.next();
			args.assert_end();

			var filter = "body|" + ByteUtils.to_string(filter_tail);
			var variable = new Variable(ByteUtils.from_string(filter));

			WordIter? endtoken;
			var body = parser.parse("endfilter", out endtoken);
			if (endtoken == null) throw new SyntaxError.UNBALANCED_TAGS(
					"{%% filter %%} must be closed with a {%% endfilter %%} tag");

			return new FilterTag(variable, body);
		}
	}
	private class FilterTag : Template {
		private Variable filter;
		private Template body;
		public FilterTag(Variable filter, Template body) {
			this.filter = filter;
			this.body = body;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			var capture = new CaptureWriter();
			yield body.exec(ctx, capture);
			var text = capture.grab_data();

			var fake_ctx = ByteUtils.create_map<Data.Data>();
			fake_ctx[ByteUtils.from_string("body")] = new Data.Substr(text);
			yield filter.exec(new Data.Mapping(fake_ctx), output);
		}
	}

	private class FirstOfBuilder : TagBuilder, Object {
		public Template? build(Parser parse, WordIter args) throws SyntaxError {
			var variables = new Gee.ArrayList<Variable>();
			foreach (var arg in args) {
				variables.add(new Variable(arg));
			}
			return new FirstOfTag(variables.to_array());
		}
	}
	private class FirstOfTag : Template {
		private Variable[] candidates;
		public FirstOfTag(Variable[] vars) {
			this.candidates = vars;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			foreach (var candidate in candidates) {
				var val = candidate.eval(ctx);
				if (val.exists) {
				    yield candidate.exec(ctx, output);
				    break;
			    }
			}
		}
	}

	private class ForBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args_iter) throws SyntaxError {
			Bytes[] args = args_iter.collect();
			var keyvar = ByteUtils.from_string("");
			if (args.length == 4) {
				// Extract he key variable and normalize
				// 		the {% for (key) (value) in (var) %} syntactic variant.
				keyvar = args[0];
				args = {args[1], args[2], args[3]};
			}

			if (args.length != 3) throw new SyntaxError.INVALID_ARGS(
					"{%% for  %%} expects either 3 or 4 arguments, got %i",
					args.length);
			if (!ByteUtils.equals_str(args[1], "in"))
				throw new SyntaxError.INVALID_ARGS(
						"{%% for %%} expects the second to lTemplate argument to be "
						+ "the word 'in', got '%s'",
						ByteUtils.to_string(args[1]));

			var target_var = args[0];
			var collection = new Variable(args[2]);

			WordIter? endtoken;
			var body = parser.parse("endfor empty", out endtoken);
			var endtag = endtoken.next();

			Template empty_block = new Echo(ByteUtils.from_string(""));
			if (ByteUtils.equals_str(endtag, "empty")) {
				endtoken.assert_end();

				empty_block = parser.parse("endfor", out endtoken);
				endtag = endtoken.next();
			}

			if (endtoken == null)
				throw new SyntaxError.UNBALANCED_TAGS(
						"{%% for %%} must be closed with a {%% endfor %%} tag");
            endtoken.assert_end();
			return new ForTag(keyvar, target_var, collection, body, empty_block);
		}
	}
	private class ForTag : Template {
		private Bytes keyvar;
		private Bytes valuevar;
		private Variable collection;
		private Template body;
		private Template empty_block;
		public ForTag(Bytes keyvar, Bytes valuevar, Variable collection,
				Template body, Template empty_block) {
			this.keyvar = keyvar;
			this.valuevar = valuevar;
			this.collection = collection;
			this.body = body;
			this.empty_block = empty_block;
		}

		private struct KeyValue {public Bytes key; public Data.Data val;}

		public override async void exec(Data.Data ctx, Writer output) {
			Gee.Map<Bytes, Data.Data> local_vars =
					ByteUtils.create_map<Data.Data>();
			Data.Data local_context = new Data.Stack.with_map(ctx, local_vars);
			var isempty = true;

            // To accommodate filters, foreach_map can't handle async,
            //      so split this loop in two.
            var to_exec = new Gee.ArrayList<KeyValue?>();
			collection.eval(ctx).foreach_map((key, val) => {
				isempty = false;
				to_exec.add(KeyValue() {key = key, val = val});
				return false; // AKA continue;
			});
			foreach (var entry in to_exec) {
			    local_vars[keyvar] = new Data.Substr(entry.key);
			    local_vars[valuevar] = entry.val;
			    yield body.exec(local_context, output);
		    }

			if (isempty) yield empty_block.exec(ctx, output);
		}
	}

	private class IfBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
			var expression = new Expression.Parser(args).expression();
			args.assert_end();

			WordIter? endtoken;
			var true_branch = parser.parse("elif else endif", out endtoken);
			var end_tag = endtoken.next();

			Template false_branch = new Echo(ByteUtils.from_string(""));
			if (ByteUtils.equals_str(end_tag, "elif")) {
			    false_branch = build(parser, endtoken);
		    } else if (ByteUtils.equals_str(end_tag, "else")) {
                endtoken.assert_end();

				false_branch = parser.parse("endif", out endtoken);
				end_tag = endtoken.next();
			}

			if (!ByteUtils.equals_str(end_tag, "endif") &&
			        !ByteUtils.equals_str(end_tag, "elif"))
				throw new SyntaxError.UNBALANCED_TAGS(
						"{%% if %%} must be closed with a {%% endif %%}");
			if (ByteUtils.equals_str(end_tag, "endif"))
			    endtoken.assert_end();

			return new IfTag(expression, true_branch, false_branch);
		}
	}
	private class IfTag : Template {
		private Expression.Expression expression;
		private Template true_branch;
		private Template false_branch;
		public IfTag(Expression.Expression exp, Template yes, Template no) {
			this.expression = exp;
			this.true_branch = yes;
			this.false_branch = no;
		}

		public override async void exec(Data.Data ctx, Writer stream) {
			if (expression.eval_type(Expression.TypePreference.BOOL, ctx) != 0)
			    yield this.true_branch.exec(ctx, stream);
			else yield this.false_branch.exec(ctx, stream);
		}
	}

	private class IfChangedBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
			var variables = new Gee.ArrayList<Variable>();
			foreach (var arg in args) {
				variables.add(new Variable(arg));
			}

			WordIter? endtoken;
			var true_branch = parser.parse("endif else", out endtoken);
			var endtag = endtoken.next();

			Template false_branch = new Echo(ByteUtils.from_string(""));
			if (ByteUtils.equals_str(endtag, "else")) {
                endtoken.assert_end();
				false_branch = parser.parse("endif", out endtoken);
				endtag = endtoken.next();
			}

			if (endtoken == null) throw new SyntaxError.UNBALANCED_TAGS(
					"{%% ifchanged %%} must be closed with an {%% endif %%} tag.");
            endtoken.assert_end();
			return new IfChangedTag(variables.to_array(),
			        true_branch, false_branch);
		}
	}
	private class IfChangedTag : Template {
		private string[]? last_values = null;
		private Variable[] test_vars;
		private Template ifchanged;
		private Template ifunchanged;
		public IfChangedTag(Variable[] vars,
		        Template true_branch, Template false_branch) {
			this.test_vars = vars;
			this.ifchanged = true_branch;
			this.ifunchanged = false_branch;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			var changed = false;
			if (last_values == null) {
				last_values = new string[test_vars.length];
				changed = true;
			}

			for (var i = 0; i < test_vars.length; i++) {
				var val = test_vars[i].eval(ctx).to_string();
				if (val == last_values[i]) continue;

				changed = true;
				last_values[i] = val;
			}

			if (changed) yield ifchanged.exec(ctx, output);
			else yield ifunchanged.exec(ctx, output);
		}
	}

	// Includes custom tags from another template
	// Requires a loading engine to work
	/*private class IncludeBuilder : TagBuilder, Object {
		public AST? build(Parser parser, WordIter args_iter) throws SyntaxError {
		    var args = args_iter.collect();
			if (ByteUtils.equals_str(args[args.length - 2], "from")) {
				ext_lib = *load(args[args.length - 1]);
				for (var name in args[0:args.length - 2]) {
					parser.local_tag_lib[name] = ext_lib.local_tag_lib[name];
				}
			} else {
				for (var arg in args) {
					ext_lib = *load(arg);
					for (var entry in ext_lib.local_tag_lib) {
						parser.local_tag_lib[name] = ext_lib.local_tag_lib[name];
					}
				}
			}
			return null;
		}
	}
	* indicates the missing piece. */

	// {% lorem [count] [w|p|*b] random? %} could be useful 

	private class NowBuilder : TagBuilder, Object {
		public Template? build(Parser parse, WordIter args) throws SyntaxError {
		    var format = args.next();
		    args.assert_end();
			return new NowTag(ByteUtils.parse_string(format));
		}
	}
	private class NowTag : Template {
		private string format;
		public NowTag(string arg) {
			this.format = arg;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			var text = new DateTime.now(new TimeZone.local()).format(format);
			yield output.writes(text);
		}
	}

	private class TemplateTagBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
		    var variant = args.next();
		    args.assert_end();
			return new TemplateTagTag(variant);
		}
	}
	private class TemplateTagTag : Template {
		private string escape;
		public TemplateTagTag(Bytes esc) {
			this.escape = ByteUtils.to_string(esc);
		}

		public override async void exec(Data.Data ctx, Writer output)
				 {
			switch(escape) {
			case "openblock": yield output.writes("{%"); break;
			case "closeblock": yield output.writes("%}"); break;
			case "openvariable": yield output.writes("{{"); break;
			case "closevariable": yield output.writes("}}"); break;
			case "openbrace": yield output.writes("{"); break;
			case "closebrace": yield output.writes("}"); break;
			case "opencomment": yield output.writes("{#"); break;
			case "closecomment": yield output.writes("#}"); break;
			}
		}
	}

	private class TestBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
		    var caption = ByteUtils.parse_string(args.next());
		    var flag = args.next_value();
		    args.assert_end();

			bool reset = false;
			bool ignore = false;
			if (flag == null) {/* ignore */}
			else if (ByteUtils.equals_str(flag, "reset")) reset = true;
			else if (ByteUtils.equals_str(flag, "ignore")) ignore = true;
			else throw new SyntaxError.INVALID_ARGS(
					"If specified, the flag argument must be either " +
					"'reset' or 'ignore', got '%s'", ByteUtils.to_string(flag));

			WordIter? endtoken;
			Bytes test_source;
			Template testcase;
			try {
				testcase = parser.parse("input output", out endtoken,
						out test_source);
			} catch (SyntaxError e) {
			    var lexer = parser.lex;
			    var failed_token = lexer.text.slice(lexer.last_start,
			            lexer.last_end);
				var try_again = true;
				while (try_again) {
					try {
						parser.parse("endtest", out endtoken);
						try_again = false;
					} catch (SyntaxError e) {/* ignore */}
				}
				if (endtoken == null)
					throw new SyntaxError.UNBALANCED_TAGS(
						"{%% test %%} must be closed with a {%% endtest %%} tag.");

				return new TestSyntaxError(caption, failed_token, ignore, e);
			}
			Bytes endtag = endtoken.next();
			endtoken.assert_end();

			Data.Data input = new Data.Empty();
			Bytes input_text = new Bytes("".data);
			if (ByteUtils.equals_str(endtag, "input")) {
				input_text = parser.scan_until("output", out endtoken);
				endtag = endtoken.next();
				endtoken.assert_end();

				var json_parser = new Json.Parser();
				try {
					json_parser.load_from_data((string) input_text.get_data(),
							input_text.length);
				} catch (Error e) {
					throw new SyntaxError.UNEXPECTED_CHAR(
							"{%% test %%}: Content of the {%% input %%} block " +
							"must be valid JSON: %s", e.message);
				}
				input = new Data.JSON(json_parser.get_root());
			}

			if (endtag == null)
				throw new SyntaxError.UNBALANCED_TAGS(
						"{%% test %%} expects an {%% output %%} branch");
			Bytes output = parser.scan_until("endtest", out endtoken);

			if (endtoken == null)
				throw new SyntaxError.UNBALANCED_TAGS(
						"{%% test %%} requires a closing {%% endtest %%} tag");
			endtoken.next(); endtoken.assert_end();
			return new TestTag(reset, ignore, caption, testcase, test_source,
					input, input_text, output);
		}
	}
	private class TestTag : Template {
		private bool reset;
		private bool ignore;
		private Bytes caption;
		private Template testcase;
		private Bytes test_source;
		private Data.Data input;
		private Bytes input_text;
		private Bytes output;
		public TestTag(bool reset, bool ignore, string caption,
		        Template testcase, Bytes test_source, Data.Data input,
		        Bytes input_text, Bytes output) {
			this.reset = reset;
			this.ignore = ignore;
			this.caption = ByteUtils.from_string(caption);
			this.testcase = testcase;
			this.test_source = test_source;
			this.input = input;
			this.input_text = input_text;
			this.output = output;
		}
		
		public static int passed;
		public static int count;

		public override async void exec(Data.Data ctx, Writer stream) {
			if (reset) {
				passed = 0;
				count = 0;
			}

			var capture = new CaptureWriter();
			yield testcase.exec(input, capture);
			Bytes computed = capture.grab_data();

			Diff.Ranges diff;
			bool passed;
			if (computed.compare(output) == 0) {
				// Fast & thankfully common case
				passed = true;
				diff = Diff.Ranges();
			} else {
				diff = Diff.diff(output, computed);
				passed = diff.a_ranges.size == 0 && diff.b_ranges.size == 0;
				assert(!passed); // Do the fast & slow checks agree?
			}

			if (!ignore) {
				if (passed) TestTag.passed++;
				TestTag.count++;
			}
			yield format_results(passed, stream, computed, diff);
		}

		private async void format_results(bool passed, Writer stream,
				Bytes computed, Diff.Ranges diff)  {
			yield stream.writes("<details");
			if (ignore) yield stream.writes(" style='opacity: 75%;'");
			yield stream.writes(">\n\t<summary style='background: ");
			yield stream.writes((passed ? "green" : "red"));
			yield stream.writes(";' title='");
			if (ignore) yield stream.writes("Ignored ");
			yield stream.writes(passed ? "PASS" : "FAILURE");
			yield stream.writes("'>");
			yield ByteUtils.write_escaped_html(caption, stream);
			yield stream.writes("</summary>\n\t");	

			yield stream.writes("<table>\n\t\t");
			yield stream.writes("<tr><th>Test Code</th>");
			yield stream.writes("<th>Test Input</th></tr>\n\t\t");
			yield stream.writes("<tr><td><pre>");
			yield ByteUtils.write_escaped_html(test_source, stream);
			yield stream.writes("</pre></td><td><pre>");
			yield ByteUtils.write_escaped_html(input_text, stream);
			yield stream.writes("</pre></td></tr>\n\t\t");

			yield stream.writes("<tr><th>Computed</th>");
			yield stream.writes("<th>Expected</th></tr>\n\t\t");
			yield stream.writes("<tr><td><pre>");
			yield Diff.render_ranges(computed, diff.b_ranges, "ins", stream);
			yield stream.writes("</pre></td><td><pre>");
			yield Diff.render_ranges(output, diff.a_ranges, "del", stream);
			yield stream.writes("</pre></td></tr>\n\t");
			yield stream.writes("</table>\n</details>");
		}
	}
	private class TestSyntaxError : Template {
		private SyntaxError error;
		private bool ignore;
		private Bytes caption;
		private Bytes failed_tag;
		public TestSyntaxError(string caption, Bytes failed_tag,
		        bool ignore, SyntaxError e) {
			this.error = e;
			this.ignore = ignore;
			this.caption = ByteUtils.from_string(caption);
			this.failed_tag = failed_tag;
		}

		public override async void exec(Data.Data ctx, Writer stream) {
			yield stream.writes("<details");
			if (ignore) yield stream.writes(" style='opacity: 75%'");
			yield stream.writes(">\n\t<summary style='background: yellow' title='");
			if (ignore) yield stream.writes("Ignored ");
			yield stream.writes("ERROR'>");
			yield ByteUtils.write_escaped_html(caption, stream);
			yield stream.writes("</summary>\n\t<h3>");
			yield stream.writes(error.domain.to_string());
			yield stream.writes(" thrown :: While Parsing <code>");
			yield stream.write(failed_tag);
			yield stream.writes("</code></h3>\n\t<p>");
			yield ByteUtils.write_escaped_html(
			        ByteUtils.from_string(error.message), stream);
			yield stream.writes("</p>\n</details>");

			// Report as failure to the stats
			if (!ignore) TestTag.count++;
		}
	}

	private class TestReportBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
            args.assert_end();
			return new TestReportTag();
		}
	}
	private class TestReportTag : Template {
		public override async void exec(Data.Data ctx, Writer output) {
			var passed = TestTag.passed == TestTag.count;
			yield output.writes("<aside style='background: ");
			yield output.writes(passed ? "green" : "red");
			yield output.writes("; position: fixed; top: 10px; right: 10px; ");
			yield output.writes("padding: 10px;'>");
			yield output.writes(TestTag.passed.to_string());
			yield output.writes("/");
			yield output.writes(TestTag.count.to_string());
			yield output.writes(" passed</aside>\n<script>document.title = '");
			yield output.writes(passed ? "Tests PASSED" : "Tests FAILED");
			yield output.writes("';\n\t");
			yield output.writes("document.querySelector");
			yield output.writes("(\"link[rel*='icon']\").href = ");
			yield output.writes("'oddysseus:debugging/");
			yield output.writes(passed ? "passed.ico" : "failed.ico");
			yield output.writes("';</script>");
		}
	}

	private class VerbatimBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
			args.assert_end();
			WordIter? endtoken;
			Bytes bodytext = parser.scan_until("endverbatim", out endtoken);
			if (endtoken == null) throw new SyntaxError.UNBALANCED_TAGS(
					"{%% verbatim %%} must be closed with a balanced " +
					"{%% endverbatim %%} tag.");
			return new Echo(bodytext);
		}
	}

	private class WithBuilder : TagBuilder, Object {
		public Template? build(Parser parser, WordIter args) throws SyntaxError {
			var parameters = parse_params(args);

			WordIter? endtoken;
			var body = parser.parse("endwith", out endtoken);
			if (endtoken == null) throw new SyntaxError.UNBALANCED_TAGS(
					"{%% with %%} must be closed with a {%% endwith %%} tag.");

			return new WithTag(parameters, body);
		}
	}
	private class WithTag : Template {
		private Gee.Map<Bytes,Variable> vars;
		private Template body;
		public WithTag(Gee.Map<Bytes,Variable> variables, Template bodyblock) {
			this.vars = variables;
			this.body = bodyblock;
		}

		public override async void exec(Data.Data ctx, Writer output) {
			yield body.exec(new Data.Lazy(vars, ctx), output);
		}
	}



	private class AddFilter : Filter {
		public override Data.Data filter(Data.Data a, Data.Data b) {
			return new Data.Literal(a.to_double() + b.to_double());
		}
	}

	private class CapFirstFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
			var text = a.to_string();
			int index = 0;
			unichar c;
			text.get_next_char(ref index, out c);
			return new Data.Literal(@"$(c.toupper())$(text.substring(index))");
		}
	}

	private class CutFilter : Filter {
		public override Data.Data filter(Data.Data a, Data.Data b) {
			var A = a.to_string();
			var B = b.to_string();
			return new Data.Literal(A.replace(B, ""));
		}
	}

	private class DateFilter : Filter {
		public override Data.Data filter(Data.Data date, Data.Data format) {
			var datetime = new DateTime.from_unix_local(date.to_int());
			var ret = datetime.format(format.to_string());
			return new Data.Literal(ret);
		}
	}

	private class DefaultFilter : Filter {
		public override Data.Data filter(Data.Data main, Data.Data @default) {
			if (main.exists) return main;
			else return @default;
		}
	}

	private class DiffFilter : Filter {
		public override Data.Data filter(Data.Data a, Data.Data b) {
			var A = a.to_bytes(); var B = b.to_bytes();

		    var loop = new MainLoop();
		    AsyncResult? result = null;
		    diff_to_str.begin(A, B, Diff.diff(A, B), (obj, res) => {
		        result = res;
		        loop.quit();
	        });
		    loop.run();
		    return new Data.Substr(diff_to_str.end(result));
		}

		private async Bytes diff_to_str(Bytes a, Bytes b, Diff.Ranges diff) {
		    var output = new CaptureWriter();
		    yield Diff.render_ranges(a, diff.a_ranges, "-", output);
		    yield output.writes("\t");
		    yield Diff.render_ranges(b, diff.b_ranges, "+", output);
		    return output.grab_data();
	    }
	}

	private class EscapeFilter : Filter {
		public override bool? should_escape() {return true;}
	}

	private class FileSizeFormatFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
			double KB = 1 << 10;
			double MB = 1 << 20;
			double GB = 1 << 30;
			double TB = 1 << 40;
			double PB = 1 << 50;

			// Doesn't make much sense to be able to handle partial bytes,
			// 		but doubles make the formatting nicer.
			var bytes = a.to_double();
			var ret = "";
			// Handle negative numbers
			var negative = bytes < 0;
			if (negative) bytes = -bytes;

			// TODO i18n
			if (bytes == 1) ret = "1 byte";
			else if (bytes < KB) ret = @"$bytes bytes";
			else if (bytes < MB) ret = "%.1fKB".printf(bytes/KB);
			else if (bytes < GB) ret = "%.1fMB".printf(bytes/MB);
			else if (bytes < TB) ret = "%.1fGB".printf(bytes/GB);
			else if (bytes < PB) ret = "%.1fTB".printf(bytes/TB);
			else ret = "%.1fPB".printf(bytes/PB);
			
			if (negative) ret = @"-$ret";
			return new Data.Literal(ret);
		}
	}

	private class FirstFilter : Filter {
		private Bytes key;
		construct {
			key = ByteUtils.from_string("$0");
		}

		public override Data.Data filter0(Data.Data a) {
			return a[this.key];
		}
	}

	private class FloatFormatFilter : Filter {
		public override Data.Data filter(Data.Data a, Data.Data places) {
			string ret;
			if (places is Data.Empty) {
				ret = "%.1f".printf(a.to_double());
				if (ret[ret.length - 1] == 0)
					ret = "%.0f".printf(a.to_double());
			} else {
				ret = "%%.%if".printf(places.to_int()).printf(a.to_double());
			}
			return new Data.Literal(ret);
		}
	}

    private class ForceEscape : Filter {
        public override bool? should_escape() {return false;}

        public override Data.Data filter(Data.Data a, Data.Data mode) {
            var loop = new MainLoop();
            AsyncResult? result = null;
            escape.begin(a.to_bytes(), AutoescapeBuilder.modes[mode.to_bytes()],
                    (obj, res) => {
                result = res;
                loop.quit();
            });
            loop.run();
            return new Data.Substr(escape.end(result));
        }

        private async Bytes escape(Bytes text, Gee.Map<char,string> escapes) {
            var capture = new CaptureWriter();
            yield ByteUtils.write_escaped(text, escapes, capture);
            return capture.grab_data();
        }
    }

	private class IRIEncodeFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
			// TODO Call into libsoup
			return a;
		}
	}

	private class JoinFilter : Filter {
		public override Data.Data filter(Data.Data list, Data.Data sep) {
			var sep_str = sep.to_string();
			var ret = "";
			var first = true;
			list.foreach_map((key, val) => {
				if (!first) ret += sep_str;
				else first = false;
				ret += val.to_string();
				return false; // AKA continue;
			});
			return new Data.Literal(ret);
		}
	}

	private class LastFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
			// This is more inneficient than is often needed,
			// 		But avoids complicating the datamodel further.
			Data.Data ret = new Data.Empty();
			a.foreach_map((key, val) => {ret = val; return false;});
			return ret;
		}
	}

	private class LengthFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
		    bool is_length;
			int ret = a.to_int(out is_length); 

			if (!is_length) {
			    ret = 0;
			    a.foreach_map((key, val) => {ret++; return false;});
		    }
			return new Data.Literal(ret);
		}
	}

	private class LengthIsFilter : Filter {
		private LengthFilter length_filter;
		construct {
			length_filter = new LengthFilter();
		}

		public override Data.Data filter(Data.Data a, Data.Data b) {
			var length = length_filter.filter0(a);
			return new Data.Literal(length.to_int() == b.to_int());
		}
	}

	private class LineBreaksFilter : Filter {
		public override Data.Data filter0(Data.Data text) {
			var paragraphs = text.to_string().split("\n\n");
			var ret = "";
			foreach (var paragraph in paragraphs) {
				ret += "<p>";
				ret += paragraph.strip().replace("\n", "<br />");
				ret += "</p>\n";
			}
			return new Data.Literal(ret);
		}
	}

	private class LineNumbersFilter : Filter {
		public override Data.Data filter0(Data.Data text) {
			var lines = text.to_string().split("\n");
			var ret = "";
			for (var i = 0; i < lines.length; i++) {
				ret += "%i. ".printf(i + 1);
				ret += lines[i];

				// Replace newlines on all but the first & last lines.
				if (i < lines.length - 1) ret += "\n";
			}
			return new Data.Literal(ret);
		}
	}

	private class LookupFilter : Filter {
		public override Data.Data filter(Data.Data a, Data.Data expression) {
			return a.lookup(expression.to_string());
		}
	}

	private class LowerFilter : Filter {
		public override Data.Data filter0(Data.Data text) {
			return new Data.Literal(text.to_string().down());
		}
	}

	// TODO Ensure Data.Literal converts values to strings before lookup
	//		In order to replicate make_list in the data model.
	private class SafeFilter : Filter {
		public override bool? should_escape() {return false;}
	}

	private class StringFormatFilter : Filter {
		public override Data.Data filter(Data.Data num, Data.Data format) {
			var ret = ("%" + format.to_string()).printf(num.to_double());
			return new Data.Literal(ret);
		}
	}

	private class TitleFilter : Filter {
		public override Data.Data filter0(Data.Data a) {
			var builder = new StringBuilder();
			var text = a.to_string();
			int index = 0;
			unichar c;
			bool capitalize = true;
			while (text.get_next_char(ref index, out c)) {
				if (capitalize) {
					c = c.totitle();
					capitalize = false;
				} else {
					c = c.tolower();
					capitalize = c.isspace();
				}
				builder.append_unichar(c);
			}
			return new Data.Literal(builder.str);
		}
	}
	// URL encode?
	



	public Gee.Map<char,string> escape_html;
	public Gee.Map<char,string> escape_csv;
	public Gee.Map<char,string> escape_js_string;
	public Gee.Map<char,string> escape_uri;

	public void register_standard_library() {
		var autoescape = new AutoescapeBuilder();
		register_tag("autoescape", autoescape);
		register_tag("filter", new FilterBuilder());
		register_tag("firstof", new FirstOfBuilder());
		register_tag("for", new ForBuilder());
		register_tag("if", new IfBuilder());
		register_tag("ifchanged", new IfChangedBuilder());
		register_tag("now", new NowBuilder());
		register_tag("templatetag", new TemplateTagBuilder());
		register_tag("test", new TestBuilder()); // *
		register_tag("test-report", new TestReportBuilder()); // *
		register_tag("trans", new I18n.TransTagBuilder());
		register_tag("verbatim", new VerbatimBuilder());
		register_tag("with", new WithBuilder());

        register_filter("add", new AddFilter());
        register_filter("capfirst", new CapFirstFilter());
        register_filter("cut", new CutFilter());
        register_filter("date", new DateFilter());
        register_filter("default", new DefaultFilter());
		register_filter("diff", new DiffFilter()); // *
		register_filter("escape", new EscapeFilter());
		register_filter("filesize", new FileSizeFormatFilter());
		register_filter("first", new FirstFilter());
		register_filter("force-escape", new ForceEscape());
		register_filter("join", new JoinFilter());
		register_filter("last", new LastFilter());
		register_filter("length", new LengthFilter());
		register_filter("lengthis", new LengthIsFilter());
		register_filter("lower", new LowerFilter());
		register_filter("safe", new SafeFilter());
		register_filter("title", new TitleFilter());

		AutoescapeBuilder.modes[ByteUtils.from_string("off")] =
				Gee.Map.empty<char,string>();
		escape_html = new Gee.HashMap<char,string>();
		escape_html['<'] = "&lt;";
		escape_html['>'] = "&gt;";
		escape_html['&'] = "&amp;";
		AutoescapeBuilder.modes[ByteUtils.from_string("html")] = escape_html;
		escape_csv = new Gee.HashMap<char,string>();
		escape_csv['\''] = "\\'";
		escape_csv['"'] = "\\\"";
		AutoescapeBuilder.modes[ByteUtils.from_string("csv")] = escape_csv;
		// These escape codes taken from Django
		// https://github.com/django/django/blob/9718fa2e8abe430c3526a9278dd976443d4ae3c6/django/utils/html.py#L51
		escape_js_string = new Gee.HashMap<char,string>();
		escape_js_string['\\'] = "\\u005C";
		escape_js_string['\''] = "\\u0027";
		escape_js_string['"'] = "\\u0022";
		escape_js_string['>'] = "\\u003E";
		escape_js_string['<'] = "\\u003C";
		escape_js_string['&'] = "\\u0026";
		escape_js_string['='] = "\\u003D";
		escape_js_string['-'] = "\\u002D";
		escape_js_string[';'] = "\\u003B";
		escape_js_string['\x2028'] = "\\u2028";
		escape_js_string['\x2029'] = "\\u2029";
		// Escape every ASCII character with a value less than 32.
		for (char z = 0; z < 32; z++)
			escape_js_string[z] = "\\u%04X".printf(z);
		AutoescapeBuilder.modes[ByteUtils.from_string("js-string")] = escape_js_string;
		escape_uri = new Gee.HashMap<char,string>();
		escape_uri['\0'] = "iriencode"; // forwards to filter for special logic.
		AutoescapeBuilder.modes[ByteUtils.from_string("url")] = escape_uri;
		AutoescapeBuilder.modes[ByteUtils.from_string("uri")] = escape_uri;

		// * indicates the tag or filter was added for use by the testrunner.
	}
}