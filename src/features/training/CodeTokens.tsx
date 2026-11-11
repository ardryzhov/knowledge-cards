// Небольшое текстовое выделение кода; токены выводятся как текст React, без HTML.
const tokenPattern = /(\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:const|let|var|function|return|if|else|new|import|from|export|default)\b|\b\d+\b|\b[A-Za-z_$][\w$]*(?=\s*\())/g

export function CodeTokens({ code }: { code: string }) {
  const parts = code.split(tokenPattern)
  return <>{parts.map((part, index) => {
    if (index % 2 === 0) return part
    const kind = part.startsWith('//') ? 'comment' : /^["']/.test(part) ? 'string' : /^\d/.test(part) ? 'number' : /^(const|let|var|function|return|if|else|new|import|from|export|default)$/.test(part) ? 'keyword' : 'function'
    return <span key={index} className={`training-code-${kind}`}>{part}</span>
  })}</>
}
