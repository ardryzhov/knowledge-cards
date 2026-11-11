import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import rehypeSanitize from 'rehype-sanitize'
import { CodeTokens } from './CodeTokens'

export function MarkdownAnswer({ answer, code }: { answer: string; code?: string }) {
  return <div className="training-markdown">
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      rehypePlugins={[rehypeSanitize]}
      components={{
        a: ({ children, href, title }) => <a href={href} title={title} target="_blank" rel="noopener noreferrer">{children}</a>,
        code: ({ children, className }) => <code className={className}><CodeTokens code={String(children)} /></code>,
      }}
    >{answer}</ReactMarkdown>
    {code && <pre><code><CodeTokens code={code} /></code></pre>}
  </div>
}
