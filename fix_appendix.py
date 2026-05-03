import re

with open('baocao/chapters/appendix.tex', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix headers
if '\\markboth' not in content:
    content = content.replace('\\chapter*{Phụ lục}\n', '\\chapter*{Phụ lục}\n\\markboth{PHỤ LỤC}{PHỤ LỤC}\n')

# Fix Table 1
content = re.sub(
    r'\\begin\{table\}\[htbp\]\s*\\centering\s*\\caption\{([^\}]+)\}',
    r'\\begin{center}\n\\captionof{table}{\1}',
    content
)
content = content.replace('\\end{table}', '\\end{center}')

with open('baocao/chapters/appendix.tex', 'w', encoding='utf-8') as f:
    f.write(content)
