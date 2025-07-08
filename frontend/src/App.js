import React, { useState, useEffect } from 'react';

function App() {
  const [question, setQuestion] = useState('');
  const [answer, setAnswer] = useState('Ask me a question about your financial documents!');
  const [isLoading, setIsLoading] = useState(false);
  const [apiEndpoint, setApiEndpoint] = useState(''); // This will be set by GitHub Actions

  useEffect(() => {
    // In a real scenario, this would be injected by your CI/CD pipeline
    // or fetched from a config service. For now, we'll use a placeholder
    // that GitHub Actions will replace.
    const injectedApiEndpoint = process.env.REACT_APP_API_ENDPOINT;
    if (injectedApiEndpoint) {
      setApiEndpoint(injectedApiEndpoint);
    } else {
      console.warn("REACT_APP_API_ENDPOINT is not set. Please ensure it's configured in your CI/CD.");
      // Fallback for local development if needed, but not for deployment
      setApiEndpoint("http://localhost:8080/ask"); // Replace with your local backend URL if testing locally
    }
  }, []);


  const handleAsk = async () => {
    if (!question.trim()) return;
    if (!apiEndpoint) {
      setAnswer("API endpoint not configured. Cannot send request.");
      return;
    }

    setIsLoading(true);
    setAnswer('Thinking...');

    try {
      const response = await fetch(apiEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ query: question }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || `HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      setAnswer(data.answer);
    } catch (error) {
      console.error('Error asking question:', error);
      setAnswer(`Error: ${error.message}. Please try again.`);
    } finally {
      setIsLoading(false);
      setQuestion(''); // Clear input after asking
    }
  };

  return (
    <div className="flex flex-col h-full w-full bg-white rounded-xl shadow-lg p-6">
      <h1 className="text-3xl font-bold text-gray-800 mb-6 text-center">
        Financial Document AI Assistant
      </h1>

      {/* Answer Display Area */}
      <div className="flex-grow bg-gray-50 rounded-lg p-4 mb-6 overflow-y-auto shadow-inner border border-gray-200">
        <p className="text-gray-700 whitespace-pre-wrap">{answer}</p>
      </div>

      {/* Input and Button */}
      <div className="flex flex-col sm:flex-row gap-4">
        <input
          type="text"
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          onKeyPress={(e) => {
            if (e.key === 'Enter' && !isLoading) {
              handleAsk();
            }
          }}
          placeholder="Ask a question about your financial documents..."
          className="flex-grow p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 shadow-sm text-gray-800"
          disabled={isLoading}
        />
        <button
          onClick={handleAsk}
          className={`px-6 py-3 rounded-lg text-white font-semibold transition duration-300 ease-in-out
            ${isLoading ? 'bg-blue-300 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-700 shadow-md hover:shadow-lg'}`}
          disabled={isLoading}
        >
          {isLoading ? 'Asking...' : 'Ask AI'}
        </button>
      </div>
      <p className="text-sm text-gray-500 mt-2 text-center">
        AI answers are based solely on the content of the uploaded PDF documents.
      </p>
    </div>
  );
}

export default App;

