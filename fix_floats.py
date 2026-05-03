import re
import glob

for filepath in glob.glob('baocao/chapters/*.tex'):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Process figures
    parts = re.split(r'\\begin\{figure\}(?:\[.*?\])?', content)
    new_content = parts[0]
    for part in parts[1:]:
        subparts = part.split('\\end{figure}', 1)
        if len(subparts) == 2:
            fig_content, rest = subparts
            # Replace \caption{ with \captionof{figure}{
            # Need to be careful to only replace the first occurrence of \caption{
            fig_content = fig_content.replace('\\caption{', '\\captionof{figure}{', 1)
            new_content += '\\begin{center}' + fig_content + '\\end{center}' + rest
        else:
            new_content += '\\begin{figure}' + part # Fallback if no \end{figure}
            
    content = new_content
    
    # Process tables
    parts = re.split(r'\\begin\{table\}(?:\[.*?\])?', content)
    new_content = parts[0]
    for part in parts[1:]:
        subparts = part.split('\\end{table}', 1)
        if len(subparts) == 2:
            tab_content, rest = subparts
            # Replace \caption{ with \captionof{table}{
            tab_content = tab_content.replace('\\caption{', '\\captionof{table}{', 1)
            new_content += '\\begin{center}' + tab_content + '\\end{center}' + rest
        else:
            new_content += '\\begin{table}' + part # Fallback if no \end{table}
            
    content = new_content
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

print("Done fixing floats.")
